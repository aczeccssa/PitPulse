import XCTest
@testable import SharedData
@testable import PitPulseDesktop

extension AppModelTests {
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
                let body = try JSONDecoder().decode(RefreshRequest.self, from: XCTUnwrap(request.testBodyData))
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
        XCTAssertEqual(model.resultMeta?.revision, 3)
        XCTAssertEqual(requests.values, [
            "GET /api/v1/sessions/2026:1:race/results",
            "POST /api/v1/refresh",
            "GET /api/v1/sessions/2026:1:race/results",
        ])
    }

    @MainActor
    func testLateManualRefreshFailureDoesNotAffectSelectedSession() async throws {
        // A unique host keeps retry tasks left over by earlier tests from
        // polluting this test's shared URLProtocol handler.
        let host = "late-refresh-\(UUID().uuidString.lowercased()).example"
        let (model, root, suite) = makeModel(serverAddress: "https://\(host)")
        defer { cleanup(root, suite) }
        let postStarted = RequestCounter()
        let resultRequests = RequestCounter()
        URLProtocolStub.handler = { request in
            guard request.url?.host == host else { throw URLError(.badServerResponse) }
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
}
