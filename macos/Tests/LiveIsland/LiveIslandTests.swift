import AppKit
import XCTest
@testable import SharedData
@testable import PitPulseDesktop

final class LiveIslandTests: XCTestCase {
    @MainActor
    func testCollapsePreferenceAppliedBeforeNookPublishesExpandedState() {
        let suite = "LiveIslandCollapse-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: PreferenceKeys.notchAutoShowEnabled)
        let model = AppModel(defaults: defaults, reminderCenter: TestReminderCenter(), networkMonitor: TestNetworkPathMonitor(), autoBootstrap: false)
        let controller = LiveIslandController(model: model)
        controller.nook.onExpand?()
        XCTAssertTrue(controller.nook.staysExpandedOnHoverExit)
        model.setNotchCollapseOnMouseExit(true)
        controller.nook.onExpand?()
        XCTAssertFalse(controller.nook.staysExpandedOnHoverExit)
    }


    @MainActor
    func testPresentationChoicesSurviveExpandedViewRecreation() {
        let model = AppModel(reminderCenter: TestReminderCenter(), networkMonitor: TestNetworkPathMonitor(), autoBootstrap: false)
        let actions = LiveIslandActions()
        XCTAssertFalse(actions.messagesExpanded)
        let first = LiveIslandExpandedView(model: model, actions: actions)
        first.actions.mode = "Live Map"
        first.actions.selectedNumber = "3"
        first.actions.messagePage = "Team Radio"
        first.actions.messageFilter = "driver"
        first.actions.messagesExpanded = true
        actions.presentation = "hidden"
        let reopened = LiveIslandExpandedView(model: model, actions: actions)
        XCTAssertEqual(reopened.actions.mode, "Live Map")
        XCTAssertEqual(reopened.actions.selectedNumber, "3")
        XCTAssertEqual(reopened.actions.messagePage, "Team Radio")
        XCTAssertEqual(reopened.actions.messageFilter, "driver")
        XCTAssertTrue(reopened.actions.messagesExpanded)
        XCTAssertTrue(reopened.actions.map === first.actions.map)
    }

    @MainActor
    func testReopeningPostsManualPresentationRequest() {
        let request = expectation(forNotification: AppDelegate.reopenNotification, object: nil)
        XCTAssertFalse(AppDelegate().applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        wait(for: [request], timeout: 1)
    }
    func liveDriver(_ name: String) -> LiveDriver {
        LiveDriver(number: "16", name: name, team: nil, position: 3, gap: "+1.2", interval: nil, lapCount: 5, lastLap: nil, bestLap: "1:30.0")
    }

    func snapshot(status: String, type: String) -> LiveSnapshot {
        LiveSnapshot(
            schemaVersion: 1,
            stateVersion: 1,
            sessionId: "session",
            sessionName: "Race",
            sourceStatus: .connected,
            sourceMode: .live,
            statusReason: nil,
            sessionType: type,
            sessionStatus: status,
            trackStatus: nil,
            lapCount: nil,
            updatedAt: nil,
            lastTransportAt: nil,
            drivers: [],
            raceControl: nil
        )
    }

    func meeting(_ id: String, type: SessionType, start: Date, end: Date?) -> Meeting {
        let session = Session(
            id: "\(id)-session",
            meetingId: id,
            sessionType: type,
            startTime: start,
            endTime: end,
            status: .scheduled,
            jolpicaSessionId: nil,
            openf1SessionKey: nil
        )
        return Meeting(
            id: id,
            season: 2026,
            round: 1,
            name: "Australian Grand Prix",
            country: "Australia",
            countryCode: "AU",
            location: "Melbourne",
            startDate: start,
            endDate: end ?? start,
            status: .scheduled,
            sessions: [session],
            source: nil,
            fetchedAt: nil,
            sourceUpdatedAt: nil,
            revision: nil
        )
    }
}


@MainActor
final class HideDelayTestState {
    var activeSession = "session-1"
    var hideCount = 0
}
