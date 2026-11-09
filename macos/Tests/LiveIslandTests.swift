import AppKit
import XCTest
@testable import PitPulseData
@testable import PitPulseShared
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

    func testTeamAssetIDKeepsF1SeriesSeparateFromWecBrandLogos() throws {
        func driver(_ json: String) throws -> LiveDriver {
            try JSONDecoder().decode(LiveDriver.self, from: Data(json.utf8))
        }
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"1","team":"Red Bull Racing"}"#), isWec: false),
            "red_bull"
        )
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"38","team":"CADILLAC HERTZ TEAM JOTA","manufacturer":"Cadillac V-Series.R"}"#), isWec: true),
            "wec_cadillac"
        )
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"7","team":"TOYOTA RACING","manufacturer":"Toyota TR010 Hybrid"}"#), isWec: true),
            "wec_toyota"
        )
        XCTAssertNil(LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"99","team":"Unknown Team"}"#), isWec: true))
    }

    func testCarSideArtworkUsesTeamForF1AndCarNumberForWec() throws {
        func driver(_ json: String) throws -> LiveDriver {
            try JSONDecoder().decode(LiveDriver.self, from: Data(json.utf8))
        }
        XCTAssertEqual(
            LiveIslandLogic.carSideAssetID(for: try driver(#"{"number":"63","team":"Mercedes"}"#), isWec: false),
            "mercedes"
        )
        XCTAssertEqual(
            LiveIslandLogic.carSideAssetID(for: try driver(#"{"number":"1","team":"Red Bull Racing"}"#), isWec: false),
            "red_bull"
        )
        XCTAssertEqual(
            LiveIslandLogic.carSideAssetID(for: try driver(#"{"number":"38","manufacturer":"Cadillac V-Series.R"}"#), isWec: true),
            "38"
        )
        XCTAssertNil(LiveIslandLogic.carSideAssetID(for: try driver(#"{"number":"99","team":"Unknown Team"}"#), isWec: false))
    }

    func testWecTeamLogoPrefersCustomerTeamAndFallsBackToBrand() throws {
        func driver(_ json: String) throws -> LiveDriver {
            try JSONDecoder().decode(LiveDriver.self, from: Data(json.utf8))
        }
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"10","team":"GARAGE 59","manufacturer":"McLaren 720S LMGT3 Evo"}"#), isWec: true),
            "wec_garage_59"
        )
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"20","team":"BMW M TEAM WRT","manufacturer":"BMW M Hybrid V8"}"#), isWec: true),
            "wec_bmw"
        )
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"69","team":"TEAM WRT","manufacturer":"BMW M4 LMGT3 Evo"}"#), isWec: true),
            "wec_team_wrt"
        )
    }

    func testDriverAssetSlugFoldsDiacriticsUsedByWecPortraits() {
        func driver(_ name: String) throws -> LiveDriver {
            try JSONDecoder().decode(LiveDriver.self, from: Data("{\"number\":\"8\",\"name\":\"\(name)\"}".utf8))
        }
        XCTAssertEqual(LiveIslandLogic.driverAssetID(for: try! driver("Marco SØRENSEN")), "marco-sorensen")
        XCTAssertEqual(LiveIslandLogic.driverAssetID(for: try! driver("Sébastien Bourdais")), "sebastien-bourdais")
        XCTAssertEqual(LiveIslandLogic.driverAssetID(for: try! driver("Petru UMBRĂRESCU")), "petru-umbrarescu")
        XCTAssertNil(LiveIslandLogic.driverAssetID(for: LiveDriver(number: "8", name: nil, team: nil, position: nil, gap: nil, interval: nil, lapCount: nil, lastLap: nil, bestLap: nil)))
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

    func testFavoriteUsesUniqueFullNameMatchAndRejectsAmbiguity() {
        let favorite = FavoriteDriver(id: "leclerc", name: "Charles Leclerc")
        let driver = liveDriver("charles-leclerc")

        XCTAssertEqual(
            LiveIslandLogic.matchedDriver(favoriteId: "leclerc", favorites: [favorite], drivers: [driver]),
            driver
        )
        XCTAssertNil(
            LiveIslandLogic.matchedDriver(favoriteId: "leclerc", favorites: [favorite], drivers: [driver, driver])
        )
        XCTAssertNil(LiveIslandLogic.matchedDriver(favoriteId: "unknown", favorites: [favorite], drivers: [driver]))
    }

    func testHelmetRequiresUniqueRosterNameAndRejectsPartialName() {
        let roster = [FavoriteDriver(id: "leclerc", name: "Charles Leclerc")]
        XCTAssertEqual(LiveIslandLogic.rosterID(for: liveDriver("CHARLES Leclerc"), favorites: roster), "leclerc")
        XCTAssertNil(LiveIslandLogic.rosterID(for: liveDriver("Leclerc"), favorites: roster))
        XCTAssertNil(LiveIslandLogic.rosterID(for: liveDriver("Charles Leclerc"), favorites: roster + roster))
    }

    func testKimiKnownFullNameAliasMatchesHelmetAndFavoriteWithoutGuessing() {
        let roster = [FavoriteDriver(id: "antonelli", name: "Andrea Kimi Antonelli")]
        let kimi = liveDriver("Kimi ANTONELLI")
        XCTAssertEqual(LiveIslandLogic.rosterID(for: kimi, favorites: roster), "antonelli")
        XCTAssertEqual(LiveIslandLogic.matchedDriver(favoriteId: "antonelli", favorites: roster, drivers: [kimi]), kimi)
        let aliasRoster = roster + [FavoriteDriver(id: "other", name: "Kimi Antonelli")]
        XCTAssertNil(LiveIslandLogic.rosterID(for: kimi, favorites: aliasRoster))
        XCTAssertNil(LiveIslandLogic.matchedDriver(favoriteId: "antonelli", favorites: roster, drivers: [kimi, liveDriver("Andrea Kimi Antonelli")]))
        XCTAssertNil(LiveIslandLogic.rosterID(for: liveDriver("Antonelli"), favorites: roster))
        XCTAssertNil(LiveIslandLogic.rosterID(for: liveDriver("Andrea Antonelli"), favorites: roster))
    }

    func testFollowRowRequiresUniqueIdentityOnBothSides() {
        let kimi = liveDriver("Kimi Antonelli")
        let roster = [FavoriteDriver(id: "antonelli", name: "Andrea Kimi Antonelli")]
        XCTAssertEqual(LiveIslandLogic.followableDriverID(for: kimi, favorites: roster, drivers: [kimi]), "antonelli")
        XCTAssertNil(LiveIslandLogic.followableDriverID(for: kimi, favorites: [], drivers: [kimi]))
        XCTAssertNil(LiveIslandLogic.followableDriverID(for: kimi, favorites: roster, drivers: [kimi, kimi]))
        XCTAssertNil(LiveIslandLogic.followableDriverID(for: kimi, favorites: roster + roster, drivers: [kimi]))
    }

    @MainActor
    func testWecFollowUsesCarNumberAndKeepsSeriesFavoritesSeparate() {
        let kubica = LiveDriver(
            number: "83", name: "Robert Kubica", team: "AF Corse", position: 4, gap: "+1.2",
            interval: nil, lapCount: 5, lastLap: nil, bestLap: "1:30.0",
            classId: "LMGT3", className: "LMGT3", classPosition: 2
        )
        XCTAssertEqual(LiveIslandLogic.followableID(for: kubica, favorites: [], drivers: [kubica], isWec: true), "wec:83")
        XCTAssertNil(LiveIslandLogic.followableID(for: kubica, favorites: [], drivers: [kubica], isWec: false))

        let suite = "LiveIslandWecFollowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, reminderCenter: TestReminderCenter(), networkMonitor: TestNetworkPathMonitor(), autoBootstrap: false)
        model.setFavoriteDriver("max_verstappen")
        model.setFavoriteDriver("wec:83", name: "Robert Kubica", series: .wec)
        XCTAssertEqual(model.favoriteDriverId(for: .f1), "max_verstappen")
        XCTAssertEqual(model.favoriteDriverId(for: .wec), "wec:83")
        XCTAssertTrue(model.favoriteDrivers.contains { $0.id == "wec:83" && $0.name == "Robert Kubica" })
        XCTAssertEqual(
            LiveIslandLogic.matchedDriver(favoriteId: "wec:83", favorites: model.favoriteDrivers, drivers: [kubica]),
            kubica
        )
        model.setFavoriteDriver(nil, series: .wec)
        XCTAssertNil(model.favoriteDriverId(for: .wec))
        XCTAssertEqual(model.favoriteDriverId(for: .f1), "max_verstappen")
    }

    func testWecFollowFollowsTheDriverNotTheCarNumber() {
        let lynn = LiveDriver(
            number: "12", name: "Alex Lynn", team: "CADILLAC HERTZ TEAM JOTA", position: 8,
            gap: "+9.0", interval: nil, lapCount: 40, lastLap: nil, bestLap: "1:36.0",
            classId: "HYPERCAR", className: "Hypercar", classPosition: 8
        )
        let nato = LiveDriver(
            number: "12", name: "Norman Nato", team: "CADILLAC HERTZ TEAM JOTA", position: 9,
            gap: "+10.0", interval: nil, lapCount: 40, lastLap: nil, bestLap: "1:36.2",
            classId: "HYPERCAR", className: "Hypercar", classPosition: 9
        )
        let favorite = FavoriteDriver(id: "wec:12", name: "Alex Lynn")
        XCTAssertTrue(LiveIslandLogic.isFavoriteDriver(lynn, favoriteId: "wec:12", favorites: [favorite]))
        XCTAssertFalse(LiveIslandLogic.isFavoriteDriver(nato, favoriteId: "wec:12", favorites: [favorite]))
        XCTAssertNil(LiveIslandLogic.matchedDriver(favoriteId: "wec:12", favorites: [favorite], drivers: [nato]))
    }

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

    @MainActor
    func testFavoriteDriverPersistsStableIDWhenRosterIsUnavailable() {
        let suite = "LiveIslandFavoriteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            defaults: defaults,
            reminderCenter: TestReminderCenter(),
            networkMonitor: TestNetworkPathMonitor(),
            autoBootstrap: false
        )

        model.setFavoriteDriver("max-verstappen")

        XCTAssertEqual(model.favoriteDriverId, "max-verstappen")
        XCTAssertEqual(defaults.string(forKey: PreferenceKeys.favoriteDriverId), "max-verstappen")
        XCTAssertEqual(model.favoriteDrivers.first?.id, "max-verstappen")
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

    private func liveDriver(_ name: String) -> LiveDriver {
        LiveDriver(number: "16", name: name, team: nil, position: 3, gap: "+1.2", interval: nil, lapCount: 5, lastLap: nil, bestLap: "1:30.0")
    }

    private func snapshot(status: String, type: String) -> LiveSnapshot {
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

    private func meeting(_ id: String, type: SessionType, start: Date, end: Date?) -> Meeting {
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
private final class HideDelayTestState {
    var activeSession = "session-1"
    var hideCount = 0
}
