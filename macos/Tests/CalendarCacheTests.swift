import XCTest
@testable import F1Companion

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
        let (model, root, suite) = makeModel(credentials: ModelCredentials(fail: true))
        defer { cleanup(root, suite) }
        URLProtocolStub.handler = { _ in
            XCTFail("Keychain failure must stop the request")
            throw URLError(.unknown)
        }
        await model.refreshNow()
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
    private func makeModel(credentials: ModelCredentials = ModelCredentials()) -> (AppModel, URL, String) {
        let suite = "PitPulseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("https://a.example", forKey: PreferenceKeys.serverAddress)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return (AppModel(defaults: defaults, credentials: credentials,
                         cache: DiskCalendarCache(rootURL: root),
                         session: URLSession(configuration: configuration), autoBootstrap: false), root, suite)
    }

    private func cleanup(_ root: URL, _ suite: String) {
        try? FileManager.default.removeItem(at: root)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func installResponses(stale: Bool = false, delayOldServer: Bool = false) {
        URLProtocolStub.handler = { request in
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
