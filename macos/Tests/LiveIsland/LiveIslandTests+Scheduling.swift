import AppKit
import XCTest
@testable import SharedData
@testable import PitPulseDesktop

extension LiveIslandTests {
    func testDisplaySelectionPrefersBuiltInNotchThenMainAndAvailableScreen() {
        XCTAssertEqual(LiveIslandLogic.preferredScreen(in: [1, 2, 3], main: 1, hasBuiltInNotch: { $0 == 2 }), 2)
        XCTAssertEqual(LiveIslandLogic.preferredScreen(in: [1, 3], main: 3, hasBuiltInNotch: { _ in false }), 3)
        XCTAssertEqual(LiveIslandLogic.preferredScreen(in: [1], main: nil, hasBuiltInNotch: { _ in false }), 1)
        XCTAssertNil(LiveIslandLogic.preferredScreen(in: [Int](), main: nil, hasBuiltInNotch: { _ in false }))
    }

    @MainActor
    func testAutomaticShowReadsFalseCommandLineBoolean() {
        let suite = "LiveIslandCommandLineTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("NO", forKey: PreferenceKeys.notchAutoShowEnabled)
        let model = AppModel(defaults: defaults, reminderCenter: TestReminderCenter(), networkMonitor: TestNetworkPathMonitor(), autoBootstrap: false)
        XCTAssertFalse(model.notchAutoShowEnabled)
    }
    func testAutomaticShowHonorsPreferenceDismissalAndSessionChange() {
        XCTAssertFalse(LiveIslandLogic.shouldAutomaticallyShow(
            enabled: false, dismissedSessionKey: nil, sessionKey: "session-1", sessionChanged: true, isHidden: true
        ))
        XCTAssertFalse(LiveIslandLogic.shouldAutomaticallyShow(
            enabled: true, dismissedSessionKey: "session-1", sessionKey: "session-1", sessionChanged: true, isHidden: true
        ))
        XCTAssertTrue(LiveIslandLogic.shouldAutomaticallyShow(
            enabled: true, dismissedSessionKey: "session-1", sessionKey: "session-2", sessionChanged: true, isHidden: true
        ))
        XCTAssertTrue(LiveIslandLogic.shouldAutomaticallyShow(
            enabled: true, dismissedSessionKey: nil, sessionKey: "session-1", sessionChanged: false, isHidden: true
        ))
    }

    @MainActor
    func testFinishedSessionDelayCanBeCancelledOrInvalidatedBySessionSwitch() async {
        let state = HideDelayTestState()
        let cancelled = LiveIslandLogic.delayedHideTask(
            after: .milliseconds(30),
            shouldHide: { state.activeSession == "session-1" },
            hide: { state.hideCount += 1 }
        )
        cancelled.cancel()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(state.hideCount, 0)

        let switched = LiveIslandLogic.delayedHideTask(
            after: .milliseconds(1),
            shouldHide: { state.activeSession == "session-1" },
            hide: { state.hideCount += 1 }
        )
        state.activeSession = "session-2"
        await switched.value
        XCTAssertEqual(state.hideCount, 0)

        let current = LiveIslandLogic.delayedHideTask(
            after: .milliseconds(1),
            shouldHide: { state.activeSession == "session-2" },
            hide: { state.hideCount += 1 }
        )
        await current.value
        XCTAssertEqual(state.hideCount, 1)
    }

    @MainActor
    func testAutomaticShowPreferenceDefaultsOnAndPersistsChange() {
        let suite = "LiveIslandTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            defaults: defaults,
            reminderCenter: TestReminderCenter(),
            networkMonitor: TestNetworkPathMonitor(),
            autoBootstrap: false
        )

        XCTAssertTrue(model.notchAutoShowEnabled)
        model.setNotchAutoShowEnabled(false)
        XCTAssertFalse(model.notchAutoShowEnabled)
        XCTAssertFalse(defaults.bool(forKey: PreferenceKeys.notchAutoShowEnabled))
        XCTAssertFalse(model.notchCollapseOnMouseExit)
        model.setNotchCollapseOnMouseExit(true)
        let reopened = AppModel(defaults: defaults, reminderCenter: TestReminderCenter(), networkMonitor: TestNetworkPathMonitor(), autoBootstrap: false)
        XCTAssertTrue(reopened.notchCollapseOnMouseExit)
        model.setNotchCollapseOnMouseExit(false)
        XCTAssertFalse(defaults.bool(forKey: PreferenceKeys.notchCollapseOnMouseExit))
    }
}
