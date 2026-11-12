import XCTest
@testable import SharedData
@testable import PitPulseDesktop

extension AppModelTests {
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
}
