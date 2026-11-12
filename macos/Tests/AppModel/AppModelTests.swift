import XCTest
@testable import SharedData
@testable import PitPulseDesktop

final class AppModelTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    @MainActor
    func makeModel(
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

    func cleanup(_ root: URL, _ suite: String) {
        try? FileManager.default.removeItem(at: root)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    func installResponses(
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
