import XCTest
@testable import PitPulseData
@testable import PitPulseShared
@testable import PitPulseDesktop

final class CalendarCacheTests: XCTestCase {
    func testRoundTripAndCacheRevision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCalendarCache(rootURL: root)
        let server = URL(string: "https://pitpulse.example")!
        let first = TestData.envelope()
        try await cache.save(server: server, season: 2026, envelope: first, savedAt: TestData.date("2026-03-01T00:00:00Z"))

        let loaded = try await cache.load(server: server, season: 2026)
        XCTAssertEqual(loaded?.envelope.data, first.data)
        XCTAssertEqual(loaded?.savedAt, TestData.date("2026-03-01T00:00:00Z"))
    }

    func testServerAndSeasonIsolation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCalendarCache(rootURL: root)
        let serverA = URL(string: "https://a.example")!
        let serverB = URL(string: "https://b.example")!
        try await cache.save(server: serverA, season: 2026, envelope: TestData.envelope())

        let serverBResult = try await cache.load(server: serverB, season: 2026)
        let seasonResult = try await cache.load(server: serverA, season: 2027)
        XCTAssertNil(serverBResult)
        XCTAssertNil(seasonResult)
    }

    func testEndpointCacheIsIsolatedByServerSeasonAndSessionKey() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCalendarCache(rootURL: root)
        let server = URL(string: "https://a.example")!
        let row = DriverStanding(
            season: 2026, position: 1, driverId: "norris", driverName: "Lando Norris",
            constructor: "McLaren", constructorIds: ["mclaren"], points: 25, wins: 1,
            source: "fixture", fetchedAt: TestData.date("2026-03-08T00:00:00Z"), revision: 2
        )
        let envelope = APIEnvelope(data: [row], meta: TestData.meta(revision: 2))
        try await cache.save(server: server, season: 2026, key: "results-2026:1:race", envelope: envelope)

        let loaded = try await cache.load(server: server, season: 2026, key: "results-2026:1:race", as: [DriverStanding].self)
        let otherSession = try await cache.load(server: server, season: 2026, key: "results-2026:2:race", as: [DriverStanding].self)
        let otherServer = try await cache.load(server: URL(string: "https://b.example")!, season: 2026, key: "results-2026:1:race", as: [DriverStanding].self)
        XCTAssertEqual(loaded?.data, [row])
        XCTAssertNil(otherSession)
        XCTAssertNil(otherServer)
    }

    func testCorruptCacheIsRemovedAndRecoveredAsMiss() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCalendarCache(rootURL: root)
        let server = URL(string: "https://pitpulse.example")!
        try await cache.save(server: server, season: 2026, envelope: TestData.envelope())
        let fileURL = await cache.fileURL(server: server, season: 2026)
        try Data("not-json".utf8).write(to: fileURL)

        let recovered = try await cache.load(server: server, season: 2026)
        XCTAssertNil(recovered)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testAtomicWriteFailureDoesNotReplaceExistingCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("blocking-file".utf8).write(to: root)
        let cache = DiskCalendarCache(rootURL: root)
        let server = URL(string: "https://pitpulse.example")!
        do {
            try await cache.save(server: server, season: 2026, envelope: TestData.envelope())
            XCTFail("Expected cache write failure")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("v1").path))
        }
    }


}

private struct ModelCredentials: CredentialStore {
    var fail = false
    func token(for server: URL) throws -> String? {
        if fail { throw CredentialError.invalidService }
        return nil
    }
    func save(token: String, for server: URL) throws {
        if fail { throw CredentialError.invalidService }
    }
    func deleteToken(for server: URL) throws {
        if fail { throw CredentialError.invalidService }
    }
}

final class AppModelTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    @MainActor
    func testFailureDoesNotThrottleNextSuccessfulRefresh() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        URLProtocolStub.handler = { _ in throw URLError(.notConnectedToInternet) }
        await model.refreshNow()
        XCTAssertNil(model.lastSuccessfulAttemptAt)
        XCTAssertEqual(model.connectionStatus, .failed)
        installResponses()
        await model.refreshNow()
        XCTAssertNotNil(model.lastSuccessfulAttemptAt)
        XCTAssertEqual(model.connectionStatus, .connected)
        XCTAssertFalse(model.isRefreshing)
    }

    @MainActor
    func testColdStartRefreshesEvenRecentlySavedCache() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        let cache = DiskCalendarCache(rootURL: root)
        try await cache.save(server: model.serverURL!, season: model.selectedSeason,
                             envelope: TestData.envelope(meetings: [TestData.meeting(name: "Cached")]))
        installResponses()
        await model.bootstrap()
        XCTAssertEqual(model.meetings.first?.name, "a.example")
        XCTAssertEqual(model.availableResultSessions.count, 1)
        XCTAssertEqual(model.connectionStatus, .connected)
        XCTAssertNotNil(model.lastSuccessfulAttemptAt)
    }

    @MainActor
    func testOfflineColdStartPreservesLastReadableCalendar() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        try await DiskCalendarCache(rootURL: root).save(
            server: model.serverURL!, season: model.selectedSeason, envelope: TestData.envelope())
        URLProtocolStub.handler = { _ in throw URLError(.notConnectedToInternet) }
        await model.bootstrap()
        XCTAssertEqual(model.meetings.count, 1)
        XCTAssertEqual(model.connectionStatus, .stale)
        XCTAssertNil(model.lastSuccessfulAttemptAt)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testKeychainReadFailureIsVisibleWithoutNetwork() async throws {
        let host = "keychain-failure-\(UUID().uuidString.lowercased()).example"
        let (model, root, suite) = makeModel(
            credentials: ModelCredentials(fail: true),
            serverAddress: "https://\(host)"
        )
        defer { cleanup(root, suite) }
        let requests = RequestCounter()
        URLProtocolStub.handler = { request in
            if request.url?.host == host { requests.increment() }
            return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil,
                                    headerFields: nil)!, Data())
        }
        await model.refreshNow()
        XCTAssertEqual(requests.value, 0)
        XCTAssertEqual(model.connectionStatus, .failed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.lastSuccessfulAttemptAt)
    }

    @MainActor
    func testLateOldServerResponseCannotOverwriteNewServer() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        installResponses(delayOldServer: true)
        let oldRequest = Task { await model.refreshNow() }
        while !model.isRefreshing { await Task.yield() }
        XCTAssertTrue(model.updateServerAddress("https://b.example"))
        XCTAssertNil(model.lastSuccessfulAttemptAt)
        XCTAssertNil(model.lastSuccessfulLoadAt)
        await oldRequest.value
        for _ in 0..<200 {
            if model.meetings.first?.name == "b.example" && !model.isRefreshing { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.meetings.first?.name, "b.example")
        XCTAssertEqual(model.connectionStatus, .connected)
    }

    @MainActor
    func testSameRevisionRefreshUpdatesMetadataAndKeepsStaleWarning() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        installResponses()
        await model.refreshNow()
        let firstLoad = try XCTUnwrap(model.lastSuccessfulLoadAt)
        installResponses(stale: true)
        await model.refreshNow()
        XCTAssertEqual(model.meta?.revision, 1)
        XCTAssertEqual(model.meta?.stale, true)
        XCTAssertGreaterThan(try XCTUnwrap(model.lastSuccessfulLoadAt), firstLoad)
        XCTAssertEqual(model.connectionStatus, .stale)
    }

    @MainActor
    func testResultsRefreshRecognizesRevisionAndPreservesLastSuccessOnFailure() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        let fixture = MutableResultsFixture()
        URLProtocolStub.handler = { request in
            guard request.url?.path.hasSuffix("/results") == true else {
                throw URLError(.badServerResponse)
            }
            let (revision, shouldFail) = fixture.snapshot()
            if shouldFail { throw URLError(.notConnectedToInternet) }
            let row = SessionResult(
                sessionId: "2026:1:race", position: 1, classification: "classified",
                driverId: "norris", driverName: "Lando Norris", constructorId: "mclaren", team: "McLaren",
                time: nil, bestLap: "1:20.000", q1: nil, q2: nil, q3: nil, raceTime: "1:30:00.000",
                gap: nil, laps: 58, points: revision == 1 ? 25 : 26, source: "fixture",
                sourceUpdatedAt: nil, fetchedAt: TestData.date("2026-03-08T00:00:00Z"), revision: revision,
                quality: "provisional"
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let envelope = APIEnvelope(data: [row], meta: TestData.meta(revision: revision))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!, try encoder.encode(envelope))
        }

        model.selectResultSession("2026:1:race")
        for _ in 0..<100 where model.resultMeta?.revision != 1 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.resultMeta?.revision, 1)
        XCTAssertEqual(model.sessionResults.first?.points, 25)

        fixture.update(revision: 2)
        await model.refreshResults()
        XCTAssertEqual(model.resultMeta?.revision, 2)
        XCTAssertEqual(model.sessionResults.first?.points, 26)

        await model.refreshResults()
        XCTAssertEqual(model.resultMeta?.revision, 2)
        XCTAssertEqual(model.sessionResults.first?.points, 26)

        fixture.update(revision: 3, shouldFail: true)
        await model.refreshResults()
        XCTAssertEqual(model.resultMeta?.revision, 2)
        XCTAssertEqual(model.sessionResults.first?.points, 26)
        XCTAssertNotNil(model.resultError)
    }

    @MainActor
    func testManualResultsRefreshReadsCacheFirstWaitsForSyncThenReloads() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        let requests = RequestLog()
        let results = RequestCounter()
        URLProtocolStub.handler = { request in
            let path = request.url!.path
            requests.append("\(request.httpMethod ?? "GET") \(path)")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let responseData: Data
            if path == "/api/v1/refresh" {
                let body = try JSONDecoder().decode(RefreshRequest.self, from: XCTUnwrap(request.httpBody))
                XCTAssertEqual(body.target, .results)
                XCTAssertEqual(body.sessionId, "2026:1:race")
                Thread.sleep(forTimeInterval: 0.05)
                responseData = Data(#"{"target":"results","season":2026,"sessionId":"2026:1:race","status":"completed","updatedAt":"2026-10-12T00:00:00Z"}"#.utf8)
            } else if path.hasSuffix("/results") {
                results.increment()
                let resultRevision = results.value
                let row = SessionResult(
                    sessionId: "2026:1:race", position: 1, classification: "classified", driverId: "norris",
                    driverName: "Lando Norris", constructorId: "mclaren", team: "McLaren", time: nil,
                    bestLap: nil, q1: nil, q2: nil, q3: nil, raceTime: nil, gap: nil, laps: 58, points: 25,
                    source: "fixture", sourceUpdatedAt: nil, fetchedAt: TestData.date("2026-03-08T00:00:00Z"),
                    revision: resultRevision, quality: "provisional"
                )
                responseData = try encoder.encode(APIEnvelope(data: [row], meta: TestData.meta(revision: resultRevision)))
            } else {
                throw URLError(.badServerResponse)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!, responseData)
        }

        model.selectResultSession("2026:1:race")
        for _ in 0..<100 where model.resultMeta?.revision != 1 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.resultMeta?.revision, 1)
        requests.reset()

        model.refreshCurrentPage(target: .results)
        for _ in 0..<100 where model.isRefreshing {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(model.resultMeta?.revision, 2)
        XCTAssertEqual(requests.values, [
            "GET /api/v1/sessions/2026:1:race/results",
            "POST /api/v1/refresh",
            "GET /api/v1/sessions/2026:1:race/results",
        ])
    }

    @MainActor
    func testLateManualRefreshFailureDoesNotAffectSelectedSession() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        let postStarted = RequestCounter()
        let resultRequests = RequestCounter()
        URLProtocolStub.handler = { request in
            let response: HTTPURLResponse
            let data: Data
            if request.url!.path == "/api/v1/refresh" {
                postStarted.increment()
                Thread.sleep(forTimeInterval: 0.1)
                response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json", "Retry-After": "120"])!
                data = Data("{}".utf8)
            } else {
                resultRequests.increment()
                let envelope = APIEnvelope<[SessionResult]>(
                    data: [], meta: TestData.meta(revision: resultRequests.value)
                )
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
                data = try encoder.encode(envelope)
            }
            return (response, data)
        }

        model.selectResultSession("2026:1:race")
        for _ in 0..<100 where model.resultMeta == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.resultMeta?.revision, 1)

        model.refreshCurrentPage(target: .results)
        for _ in 0..<100 where postStarted.value == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(postStarted.value, 1)
        model.selectResultSession("2026:2:race")
        for _ in 0..<100 where model.resultMeta?.revision != 3 {
            try await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<100 where model.isRefreshing {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.selectedResultSessionID, "2026:2:race")
        XCTAssertEqual(model.resultMeta?.revision, 3)
        XCTAssertNil(model.resultError)
    }

    @MainActor
    func testLateOldSeasonResultCannotOverwriteNewSeason() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        let oldRequestCounter = RequestCounter()
        URLProtocolStub.handler = { request in
            let path = request.url!.path.removingPercentEncoding ?? request.url!.path
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data: Data
            if path.hasSuffix("/results") {
                let season = path.contains("2027") ? 2027 : 2026
                if season == 2026 {
                    oldRequestCounter.increment()
                    Thread.sleep(forTimeInterval: 0.15)
                }
                let row = SessionResult(
                    sessionId: "\(season):1:race", position: 1, classification: "classified",
                    driverId: "norris", driverName: "Lando Norris", constructorId: "mclaren", team: "McLaren",
                    time: nil, bestLap: nil, q1: nil, q2: nil, q3: nil, raceTime: nil,
                    gap: nil, laps: 58, points: Double(season), source: "fixture", sourceUpdatedAt: nil,
                    fetchedAt: TestData.date("2026-03-08T00:00:00Z"), revision: season, quality: "provisional"
                )
                data = try encoder.encode(APIEnvelope(data: [row], meta: TestData.meta(revision: season)))
            } else if path.hasSuffix("/next") {
                data = try encoder.encode(APIEnvelope<Meeting?>(data: nil, meta: TestData.meta()))
            } else if path.hasSuffix("/calendar") {
                data = try encoder.encode(APIEnvelope<[Meeting]>(data: [], meta: TestData.meta()))
            } else {
                data = try encoder.encode(APIEnvelope<[DriverStanding]>(data: [], meta: TestData.meta()))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!, data)
        }

        model.selectResultSession("2026:1:race")
        for _ in 0..<100 where oldRequestCounter.value == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(oldRequestCounter.value, 1)

        model.selectSeason(2027)
        model.selectResultSession("2027:1:race")
        for _ in 0..<100 where model.resultMeta?.revision != 2027 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.selectedSeason, 2027)
        XCTAssertEqual(model.resultMeta?.revision, 2027)
        XCTAssertEqual(model.sessionResults.first?.points, 2027)

        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(model.resultMeta?.revision, 2027)
        XCTAssertEqual(model.sessionResults.first?.points, 2027)
    }

    @MainActor
    func testPopupRefreshRepeatsAndStopsWhenDismissed() async throws {
        let (model, root, suite) = makeModel(popupRefreshInterval: 0.04)
        defer { model.popupDidDisappear(); cleanup(root, suite) }
        let counter = RequestCounter()
        installResponses(calendarCounter: counter)
        await model.bootstrap()
        let initialCount = counter.value

        model.popupDidAppear()
        for _ in 0..<100 where counter.value == initialCount {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(counter.value, initialCount + 1)

        model.popupDidDisappear()
        let dismissedCount = counter.value
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(counter.value, dismissedCount)
    }

    @MainActor
    func testWakeNotificationRefreshesCalendar() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        let counter = RequestCounter()
        installResponses(delayOldServer: true, calendarCounter: counter)
        await model.bootstrap()
        let initialCount = counter.value

        model.networkPathDidChange(isAvailable: false)
        XCTAssertEqual(model.connectionStatus, .offline)
        model.networkPathDidChange(isAvailable: true)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<100 where counter.value == initialCount {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(counter.value, initialCount + 1)
    }

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

    func testReminderPlannerUsesStableServerScopedIDsAndUTCInstants() throws {
        let beforeDST = TestData.session(id: "2026:1:fp1", type: .fp1, start: "2026-03-08T06:30:00Z")
        let afterDST = TestData.session(id: "2026:1:race", type: .race, start: "2026-03-08T07:30:00Z")
        let meeting = TestData.meeting(sessions: [beforeDST, afterDST])
        let now = TestData.date("2026-03-08T06:00:00Z")
        let reminders = SessionReminderPlanner.reminders(meetings: [meeting], serverIdentity: "https://a.example", season: 2026, minutesBefore: 15, now: now)
        XCTAssertEqual(reminders.count, 2)
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(newYork.component(.hour, from: beforeDST.startTime), 1)
        XCTAssertEqual(newYork.component(.hour, from: afterDST.startTime), 3)
        XCTAssertEqual(reminders[0].fireDate, beforeDST.startTime.addingTimeInterval(-15 * 60))
        XCTAssertEqual(reminders[1].fireDate, afterDST.startTime.addingTimeInterval(-15 * 60))
        XCTAssertEqual(reminders[0].identifier, SessionReminderPlanner.reminders(
            meetings: [meeting], serverIdentity: "https://a.example", season: 2026, minutesBefore: 15, now: now
        )[0].identifier)
        XCTAssertNotEqual(reminders[0].identifier, SessionReminderPlanner.reminders(
            meetings: [meeting], serverIdentity: "https://b.example", season: 2026, minutesBefore: 15, now: now
        )[0].identifier)
        let nextSeasonSession = TestData.session(id: "2027:1:fp1", meetingId: "2027:1", type: .fp1,
                                                 start: "2027-03-05T01:30:00Z")
        let nextSeason = TestData.meeting(id: "2027:1", season: 2027, sessions: [nextSeasonSession])
        XCTAssertNotEqual(reminders[0].identifier, SessionReminderPlanner.reminders(
            meetings: [nextSeason], serverIdentity: "https://a.example", season: 2027,
            minutesBefore: 15, now: now
        )[0].identifier)
        XCTAssertTrue(SessionReminderPlanner.reminders(
            meetings: [meeting], serverIdentity: "https://a.example", season: 2026,
            minutesBefore: 15, now: afterDST.startTime
        ).isEmpty)
    }

    @MainActor
    func testReminderPermissionAndRefreshReconcileChangedAndCancelledSessions() async throws {
        let center = TestReminderCenter()
        center.authorizationStatus = .notDetermined
        let (model, root, suite) = makeModel(reminderCenter: center)
        defer { cleanup(root, suite) }
        XCTAssertFalse(model.remindersEnabled)
        await model.setRemindersEnabled(true)
        XCTAssertTrue(model.remindersEnabled)
        XCTAssertEqual(center.permissionRequests, 1)

        let start = Date.now.addingTimeInterval(86_400)
        let session = Session(id: "2026:1:fp1", meetingId: "2026:1", sessionType: .fp1,
                              startTime: start, endTime: nil, status: .scheduled,
                              jolpicaSessionId: nil, openf1SessionKey: nil)
        let meeting = Meeting(id: "2026:1", season: model.selectedSeason, round: 1,
                              name: "Test GP", country: "Australia", countryCode: "AU", location: "Melbourne",
                              startDate: start, endDate: start.addingTimeInterval(86_400), status: .scheduled,
                              sessions: [session], source: "fixture", fetchedAt: Date(), sourceUpdatedAt: nil, revision: 1)
        let state = MutableMeetingFixture(meeting)
        let counter = RequestCounter()
        center.shouldFailScheduling = true
        URLProtocolStub.handler = { request in
            if request.url!.path.hasSuffix("/calendar") {
                counter.increment()
                Thread.sleep(forTimeInterval: 0.1)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let current = state.value
            let data: Data
            if request.url!.path.hasSuffix("/next") {
                data = try encoder.encode(APIEnvelope(data: Optional<Meeting>.none, meta: TestData.meta()))
            } else {
                data = try encoder.encode(APIEnvelope(data: [current], meta: TestData.meta()))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!, data)
        }
        let firstRefresh = Task { await model.refreshNow() }
        let concurrentRefresh = Task { await model.refreshNow() }
        await firstRefresh.value
        await concurrentRefresh.value
        XCTAssertEqual(counter.value, 1)
        XCTAssertNotNil(model.reminderMessage)
        XCTAssertTrue(center.scheduled.isEmpty)

        center.shouldFailScheduling = false
        await model.refreshNow()
        XCTAssertNil(model.reminderMessage)
        let original = try XCTUnwrap(center.scheduled.values.first)
        XCTAssertEqual(center.scheduled.count, 1)
        await model.refreshNow()
        XCTAssertEqual(center.scheduled.count, 1)

        let movedSession = Session(id: session.id, meetingId: session.meetingId, sessionType: session.sessionType,
                                   startTime: start.addingTimeInterval(3600), endTime: nil, status: .scheduled,
                                   jolpicaSessionId: nil, openf1SessionKey: nil)
        state.value = Meeting(id: meeting.id, season: meeting.season, round: meeting.round, name: meeting.name,
                              country: meeting.country, countryCode: meeting.countryCode, location: meeting.location,
                              startDate: meeting.startDate, endDate: meeting.endDate, status: .scheduled,
                              sessions: [movedSession], source: meeting.source, fetchedAt: Date(),
                              sourceUpdatedAt: nil, revision: 2)
        await model.refreshNow()
        XCTAssertEqual(center.scheduled.count, 1)
        XCTAssertEqual(center.scheduled[original.identifier]?.fireDate.timeIntervalSince1970 ?? 0,
                       movedSession.startTime.addingTimeInterval(-15 * 60).timeIntervalSince1970, accuracy: 1)

        XCTAssertTrue(model.updateServerAddress("https://b.example"))
        await model.refreshNow()
        let movedServer = try XCTUnwrap(center.scheduled.values.first)
        XCTAssertEqual(center.scheduled.count, 1)
        XCTAssertNotEqual(movedServer.identifier, original.identifier)

        state.value = Meeting(id: meeting.id, season: meeting.season, round: meeting.round, name: meeting.name,
                              country: meeting.country, countryCode: meeting.countryCode, location: meeting.location,
                              startDate: meeting.startDate, endDate: meeting.endDate, status: .cancelled,
                              sessions: [movedSession], source: meeting.source, fetchedAt: Date(),
                              sourceUpdatedAt: nil, revision: 3)
        await model.refreshNow()
        XCTAssertTrue(center.scheduled.isEmpty)
    }

    @MainActor
    func testDeniedReminderPermissionDoesNotEnableOrRepeatPrompt() async throws {
        let center = TestReminderCenter()
        center.authorizationStatus = .denied
        let (model, root, suite) = makeModel(reminderCenter: center)
        defer { cleanup(root, suite) }
        await model.setRemindersEnabled(true)
        await model.setRemindersEnabled(true)
        XCTAssertFalse(model.remindersEnabled)
        XCTAssertTrue(model.reminderPermissionDenied)
        XCTAssertEqual(center.permissionRequests, 0)
    }

    @MainActor
    func testTransientFailureBackoffAdvancesBeforeRecovering() async throws {
        let (model, root, suite) = makeModel(retryDelays: [0.4, 0.8, 1.2])
        defer { cleanup(root, suite) }
        let counter = RequestCounter()
        URLProtocolStub.handler = { request in
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

    @MainActor
    private func makeModel(
        credentials: ModelCredentials = ModelCredentials(),
        serverAddress: String = "https://a.example",
        popupRefreshInterval: TimeInterval = AppModel.refreshInterval,
        reminderCenter: TestReminderCenter? = nil,
        networkMonitor: TestNetworkPathMonitor? = nil,
        retryDelays: [TimeInterval] = [5, 15, 30, 60, 300]
    ) -> (AppModel, URL, String) {
        let suite = "PitPulseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(serverAddress, forKey: PreferenceKeys.serverAddress)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return (AppModel(defaults: defaults, credentials: credentials,
                         cache: DiskCalendarCache(rootURL: root),
                         reminderCenter: reminderCenter ?? TestReminderCenter(),
                         networkMonitor: networkMonitor ?? TestNetworkPathMonitor(),
                         session: URLSession(configuration: configuration),
                         popupRefreshInterval: popupRefreshInterval, retryDelays: retryDelays,
                         autoBootstrap: false), root, suite)
    }

    private func cleanup(_ root: URL, _ suite: String) {
        try? FileManager.default.removeItem(at: root)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func installResponses(
        stale: Bool = false,
        delayOldServer: Bool = false,
        calendarCounter: RequestCounter? = nil
    ) {
        URLProtocolStub.handler = { request in
            if request.url!.path.hasSuffix("/calendar") { calendarCounter?.increment() }
            if delayOldServer && request.url?.host == "a.example" {
                Thread.sleep(forTimeInterval: 0.15)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data: Data
            if request.url!.path.hasSuffix("/next") {
                data = try encoder.encode(APIEnvelope<Meeting?>(data: nil, meta: TestData.meta(stale: stale)))
            } else {
                data = try encoder.encode(APIEnvelope(data: [TestData.meeting(name: request.url!.host!)],
                                                     meta: TestData.meta(stale: stale)))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!, data)
        }
    }
}

private final class MutableResultsFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var revision = 1
    private var shouldFail = false

    func update(revision: Int, shouldFail: Bool = false) {
        lock.lock()
        self.revision = revision
        self.shouldFail = shouldFail
        lock.unlock()
    }

    func snapshot() -> (Int, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (revision, shouldFail)
    }
}

private final class MutableMeetingFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var meeting: Meeting

    init(_ meeting: Meeting) { self.meeting = meeting }
    var value: Meeting {
        get { lock.lock(); defer { lock.unlock() }; return meeting }
        set { lock.lock(); meeting = newValue; lock.unlock() }
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var requestTimes: [UInt64] = []

    var timestamps: [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return requestTimes
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        requestTimes.append(DispatchTime.now().uptimeNanoseconds)
        lock.unlock()
    }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func append(_ value: String) {
        lock.lock()
        requests.append(value)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        requests.removeAll()
        lock.unlock()
    }
}

extension CalendarCacheTests {
    func testOldCacheVersionAndSchemaAreInvalidated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCalendarCache(rootURL: root)
        let server = URL(string: "https://a.example")!
        for field in ["cacheVersion", "schemaVersion"] {
            try await cache.save(server: server, season: 2026, envelope: TestData.envelope())
            let url = await cache.fileURL(server: server, season: 2026)
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            if field == "cacheVersion" {
                json[field] = 0
            } else {
                var envelope = json["envelope"] as! [String: Any]
                var meta = envelope["meta"] as! [String: Any]
                meta[field] = 2
                envelope["meta"] = meta
                json["envelope"] = envelope
            }
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            let loaded = try await cache.load(server: server, season: 2026)
            XCTAssertNil(loaded)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }
}

extension AppModelTests {
    @MainActor
    func testTokenMutationFailuresRemainVisibleAndDoNotClaimStoredToken() {
        let (model, root, suite) = makeModel(credentials: ModelCredentials(fail: true))
        defer { cleanup(root, suite) }
        model.saveToken("test-only")
        XCTAssertFalse(model.isTokenStored)
        XCTAssertNotNil(model.settingsMessage)
        model.deleteToken()
        XCTAssertNotNil(model.settingsMessage)
        XCTAssertNil(model.lastSuccessfulAttemptAt)
    }

    @MainActor
    func testUnauthorizedRefreshKeepsCacheAndRequiresToken() async throws {
        let (model, root, suite) = makeModel()
        defer { cleanup(root, suite) }
        try await DiskCalendarCache(rootURL: root).save(
            server: model.serverURL!, season: model.selectedSeason, envelope: TestData.envelope())
        URLProtocolStub.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        await model.bootstrap()
        XCTAssertEqual(model.connectionStatus, .requiresToken)
        XCTAssertEqual(model.meetings.count, 1)
        XCTAssertNil(model.lastSuccessfulAttemptAt)
    }
}
