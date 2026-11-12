import XCTest
@testable import SharedData
@testable import PitPulseDesktop

extension AppModelTests {
    @MainActor
    func testOfflinePathLoadsCachedPagesAndRecoveryRefreshes() async throws {
        let monitor = TestNetworkPathMonitor()
        let (model, root, suite) = makeModel(networkMonitor: monitor)
        defer { cleanup(root, suite) }
        let server = model.serverURL!
        let cache = DiskCalendarCache(rootURL: root)
        let ended = TestData.session(id: "2026:1:race", type: .race, start: "2026-03-06T01:30:00Z", status: .finished)
        let meeting = TestData.meeting(sessions: [ended])
        try await cache.save(server: server, season: 2026, envelope: TestData.envelope(meetings: [meeting]))
        let result = SessionResult(
            sessionId: ended.id, position: 1, classification: "classified", driverId: "norris",
            driverName: "Lando Norris", constructorId: "mclaren", team: "McLaren", time: nil,
            bestLap: nil, q1: nil, q2: nil, q3: nil, raceTime: nil, gap: nil, laps: nil,
            points: nil, source: "fixture", sourceUpdatedAt: nil,
            fetchedAt: TestData.date("2026-03-08T00:00:00Z"), revision: 1, quality: "provisional"
        )
        let standings = DriverStanding(
            season: 2026, position: 1, driverId: "norris", driverName: "Lando Norris",
            constructor: "McLaren", constructorIds: ["mclaren"], points: 25, wins: 1,
            source: "fixture", fetchedAt: TestData.date("2026-03-08T00:00:00Z"), revision: 1
        )
        let constructor = ConstructorStanding(
            season: 2026, position: 1, constructorId: "mclaren", constructorName: "McLaren",
            points: 25, wins: 1, source: "fixture",
            fetchedAt: TestData.date("2026-03-08T00:00:00Z"), revision: 1
        )
        try await cache.save(server: server, season: 2026, key: "results-\(ended.id)",
                             envelope: APIEnvelope(data: [result], meta: TestData.meta()))
        try await cache.save(server: server, season: 2026, key: "standings-drivers",
                             envelope: APIEnvelope(data: [standings], meta: TestData.meta()))
        try await cache.save(server: server, season: 2026, key: "standings-constructors",
                             envelope: APIEnvelope(data: [constructor], meta: TestData.meta()))
        monitor.setAvailable(false)
        URLProtocolStub.handler = { _ in XCTFail("Offline bootstrap must not make network requests"); throw URLError(.notConnectedToInternet) }
        await model.bootstrap()
        XCTAssertEqual(model.connectionStatus, .offline)
        XCTAssertEqual(model.meetings, [meeting])
        XCTAssertEqual(model.sessionResults, [result])
        XCTAssertEqual(model.driverStandings, [standings])
        model.selectStandings(isConstructor: true)
        for _ in 0..<100 where model.constructorStandings.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.constructorStandings, [constructor])

        let requests = RequestCounter()
        installResponses(calendarCounter: requests)
        monitor.setAvailable(true)
        for _ in 0..<100 where requests.value == 0 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertGreaterThan(requests.value, 0)
        for _ in 0..<100 where model.connectionStatus != .connected { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.connectionStatus, .connected)
    }
    @MainActor
    func testTransientFailureBackoffAdvancesBeforeRecovering() async throws {
        // A unique host keeps retry tasks left over by earlier tests from
        // polluting this test's shared URLProtocol handler.
        // `ServerAddress` lowercases the host it builds the request URL from,
        // so the UUID has to be lowercased too or the guard never matches.
        let host = "backoff-\(UUID().uuidString.lowercased()).example"
        let (model, root, suite) = makeModel(serverAddress: "https://\(host)", retryDelays: [0.4, 0.8, 1.2])
        defer { cleanup(root, suite) }
        let counter = RequestCounter()
        URLProtocolStub.handler = { request in
            guard request.url?.host == host else { throw URLError(.badServerResponse) }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let isCalendar = request.url!.path.hasSuffix("/calendar")
            if isCalendar {
                counter.increment()
                Thread.sleep(forTimeInterval: 0.05)
            }
            let status = isCalendar && counter.value < 4 ? 503 : 200
            let data = request.url!.path.hasSuffix("/next")
                ? try encoder.encode(APIEnvelope<Meeting?>(data: nil, meta: TestData.meta()))
                : (status == 200 ? try encoder.encode(TestData.envelope()) : Data("{}".utf8))
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!, data)
        }

        await model.refreshNow()
        for _ in 0..<1000 where counter.value < 4 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(counter.value, 4)
        let timestamps = counter.timestamps
        guard timestamps.count == 4 else { return }
        for (index, delay) in [0.4, 0.8, 1.2].enumerated() {
            let elapsed = Double(timestamps[index + 1] - timestamps[index]) / 1_000_000_000
            XCTAssertGreaterThanOrEqual(elapsed, delay, "Retry advanced before its backoff")
        }
        for _ in 0..<100 where model.connectionStatus != .connected { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.connectionStatus, .connected)
    }

    @MainActor
    func testRateLimitRetryWaitsForRetryAfter() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        let counter = RequestCounter()
        URLProtocolStub.handler = { request in
            let status: Int
            var headers = ["Content-Type": "application/json"]
            if request.url!.path.hasSuffix("/calendar") {
                counter.increment()
                status = counter.value == 1 ? 429 : 200
                if status == 429 { headers["Retry-After"] = "0.15" }
            } else { status = 200 }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = request.url!.path.hasSuffix("/next")
                ? try encoder.encode(APIEnvelope<Meeting?>(data: nil, meta: TestData.meta()))
                : try encoder.encode(TestData.envelope())
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, data)
        }
        await model.refreshNow()
        XCTAssertEqual(counter.value, 1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(counter.value, 1)
        for _ in 0..<100 where counter.value < 2 { try await Task.sleep(for: .milliseconds(10)) }
        for _ in 0..<100 where model.connectionStatus != .connected { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(counter.value, 2)
        XCTAssertEqual(model.connectionStatus, .connected)
    }

    @MainActor
    func testUnauthorizedWaitsForCredentialChangeInsteadOfRetrying() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        let counter = RequestCounter()
        let pageRequests = RequestCounter()
        URLProtocolStub.handler = { request in
            if request.url!.path.hasSuffix("/calendar") { counter.increment() }
            let isNext = request.url!.path.hasSuffix("/next")
            if !request.url!.path.hasSuffix("/calendar") && !isNext { pageRequests.increment() }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let status = isNext ? 200 : 401
            let data = isNext
                ? try encoder.encode(APIEnvelope<Meeting?>(data: nil, meta: TestData.meta()))
                : Data("{}".utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!, data)
        }
        await model.refreshNow()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(pageRequests.value, 0)
        XCTAssertEqual(model.connectionStatus, .requiresToken)
    }

    @MainActor
    func testSleepCancelsInFlightCalendarRefreshAndMarksOffline() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        URLProtocolStub.handler = { request in
            Thread.sleep(forTimeInterval: 0.1)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = request.url!.path.hasSuffix("/next")
                ? try encoder.encode(APIEnvelope<Meeting?>(data: nil, meta: TestData.meta()))
                : try encoder.encode(TestData.envelope())
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!, data)
        }
        let refresh = Task { await model.refreshNow() }
        while !model.isRefreshing { await Task.yield() }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        for _ in 0..<100 where model.connectionStatus != .offline { try await Task.sleep(for: .milliseconds(5)) }
        await refresh.value
        XCTAssertEqual(model.connectionStatus, .offline)
        XCTAssertTrue(model.meetings.isEmpty)
        XCTAssertFalse(model.isRefreshing)
    }

    @MainActor
    func testLateRefreshResponseDoesNotOverwriteOfflineStatus() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        URLProtocolStub.handler = { request in
            Thread.sleep(forTimeInterval: 0.1)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = request.url!.path.hasSuffix("/next")
                ? try encoder.encode(APIEnvelope<Meeting?>(data: nil, meta: TestData.meta()))
                : try encoder.encode(TestData.envelope())
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!, data)
        }
        let refresh = Task { await model.refreshNow() }
        while !model.isRefreshing { await Task.yield() }
        model.networkPathDidChange(isAvailable: false)
        await refresh.value
        XCTAssertEqual(model.connectionStatus, .offline)
        XCTAssertEqual(model.meetings.count, 1)
    }
}
