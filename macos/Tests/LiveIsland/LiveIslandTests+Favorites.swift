import AppKit
import XCTest
@testable import SharedData
@testable import PitPulseDesktop

extension LiveIslandTests {
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
}
