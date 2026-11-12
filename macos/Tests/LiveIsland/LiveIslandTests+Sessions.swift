import AppKit
import XCTest
@testable import SharedData
@testable import PitPulseDesktop

extension LiveIslandTests {
    func testSectorSecondParsingHandlesWecLapFormats() throws {
        XCTAssertEqual(try XCTUnwrap(LiveIslandLogic.sectorSeconds("30.452")), 30.452, accuracy: 0.0005)
        XCTAssertEqual(try XCTUnwrap(LiveIslandLogic.sectorSeconds("1:34.951")), 94.951, accuracy: 0.0005)
        XCTAssertNil(LiveIslandLogic.sectorSeconds("—"))
    }

    @MainActor
    func testFollowSwitchAndClearPersistTheSameStableID() {
        let suite = "LiveIslandFollowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, reminderCenter: TestReminderCenter(), networkMonitor: TestNetworkPathMonitor(), autoBootstrap: false)
        model.setFavoriteDriver("antonelli")
        XCTAssertEqual(model.favoriteDriverId, "antonelli")
        model.setFavoriteDriver("leclerc")
        XCTAssertEqual(defaults.string(forKey: PreferenceKeys.favoriteDriverId), "leclerc")
        model.setFavoriteDriver(nil)
        XCTAssertNil(model.favoriteDriverId)
        XCTAssertNil(defaults.string(forKey: PreferenceKeys.favoriteDriverId))
    }

    func testSessionLabelCapitalizesLowercaseUpstreamValues() {
        XCTAssertEqual(LiveIslandLogic.sessionLabel("race"), "Race")
        XCTAssertEqual(LiveIslandLogic.sessionLabel("Race"), "Race")
        XCTAssertEqual(LiveIslandLogic.sessionLabel("正赛"), "正赛")
    }

    func testSessionStateRecognizesStartAndFinishOnly() {
        XCTAssertTrue(LiveIslandLogic.isStarted("Started"))
        XCTAssertTrue(LiveIslandLogic.isStarted("In Progress"))
        XCTAssertFalse(LiveIslandLogic.isStarted("Inactive"))
        XCTAssertTrue(LiveIslandLogic.isFinished("Finalised"))
        XCTAssertTrue(LiveIslandLogic.isFinished("Finished"))
        XCTAssertFalse(LiveIslandLogic.isFinished("Started"))
    }
    func testCurrentCalendarSessionRequiresUniqueKnownEndTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let current = meeting("current", type: .race, start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))
        let noEnd = meeting("no-end", type: .qualifying, start: now.addingTimeInterval(-30), end: nil)

        XCTAssertEqual(LiveIslandLogic.currentScheduledSession(in: [current], now: now)?.session.id, "current-session")
        XCTAssertNil(LiveIslandLogic.currentScheduledSession(in: [noEnd], now: now))
        XCTAssertNil(LiveIslandLogic.currentScheduledSession(in: [current, current], now: now))
    }

    func testCountryAssociationRequiresOneLiveSessionAndMatchingScheduleWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let meeting = meeting("australia", type: .race, start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))

        XCTAssertEqual(LiveIslandLogic.meeting(for: snapshot(status: "Started", type: "Race"), in: [meeting], now: now)?.id, "australia")
        XCTAssertNil(LiveIslandLogic.meeting(for: snapshot(status: "Started", type: "Practice"), in: [meeting], now: now))
        XCTAssertNil(LiveIslandLogic.meeting(for: snapshot(status: "Started", type: "Race"), in: [meeting, meeting], now: now))
    }
}
