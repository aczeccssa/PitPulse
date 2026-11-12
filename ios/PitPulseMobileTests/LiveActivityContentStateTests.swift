import SharedComponents
import XCTest
import UIKit
@testable import SharedData

final class LiveActivityContentStateTests: XCTestCase {
    @MainActor
    func testSharedCatalogLoadsHelmetsLogosAndPreservesMissingImageFallback() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for name in ["helmet-leclerc-2026", "team-logo-ferrari-2026", "series-f1", "car-side-ferrari-2026", MotorsportAssetName.brandLogoName] {
                let image = try XCTUnwrap(MotorsportImages.uiImage(named: name, traits: traits), name)
                XCTAssertGreaterThan(image.size.width, 0)
            }
        }
        XCTAssertNil(MotorsportImages.uiImage(named: "nonexistent-preview-test-image"))
    }

    func testPositionFocusFollowsContinuingLossBeyondTenSeconds() {
        var focus = IslandPositionFocus()
        focus.update(positions: ["a": 1, "b": 2, "c": 3, "d": 4, "e": 5], now: 0)
        focus.update(positions: ["a": 1, "b": 3, "c": 2, "d": 4, "e": 5], now: 3)
        XCTAssertEqual(focus.driverID, "b") // Follow the car losing the place.
        focus.update(positions: ["a": 1, "b": 4, "c": 2, "d": 3, "e": 5], now: 9)
        XCTAssertEqual(focus.driverID, "b")
        focus.update(positions: ["a": 1, "b": 5, "c": 2, "d": 3, "e": 4], now: 14)
        XCTAssertEqual(focus.driverID, "b") // Eleven seconds later, still following B.
        let settled = ["a": 2, "b": 5, "c": 1, "d": 3, "e": 4]
        focus.update(positions: settled, now: 16)
        XCTAssertEqual(focus.driverID, "b") // Other changes cannot steal the focus.
        focus.update(positions: settled, now: 23)
        XCTAssertEqual(focus.driverID, "b")
        focus.update(positions: settled, now: 24)
        XCTAssertEqual(focus.driverID, "a") // Switch only after B settles.
        focus.update(positions: settled, now: 40)
        XCTAssertEqual(focus.driverID, "a")
    }

    func testPositionFocusChoosesForemostSimultaneousChange() {
        var focus = IslandPositionFocus()
        focus.update(positions: ["a": 1, "b": 2, "c": 3, "d": 4, "e": 5], now: 0)
        focus.update(positions: ["a": 1, "b": 3, "c": 2, "d": 5, "e": 4], now: 12)
        XCTAssertEqual(focus.driverID, "b")
    }

    func testPositionModePersistsAndCompactPayloadStaysSmall() throws {
        let mode = try JSONDecoder().decode(IslandContentMode.self, from: JSONEncoder().encode(IslandContentMode.positionChanges))
        XCTAssertEqual(mode.title, "全场风云")
        let drivers = (5...11).map { PitPulseActivityAttributes.Driver(name: "Driver \($0)", position: $0, asset: "helmet-max_verstappen-2026", gap: "+12.345", positionChange: $0 == 7 ? -1 : 1) }
        let state = PitPulseActivityAttributes.ContentState(sessionName: "Race", meetingName: "São Paulo Grand Prix", statusLabel: "Live", lapLabel: "L32/71", leaderName: "Lando NORRIS", presentation: mode.rawValue, positionDrivers: drivers, positionFocus: "Driver 7", positionWindowStart: 4)
        let data = try JSONEncoder().encode(state)
        XCTAssertLessThan(data.count, 4096)
        XCTAssertEqual(try JSONDecoder().decode(PitPulseActivityAttributes.ContentState.self, from: data), state)
        XCTAssertEqual(state.compactLeadingText, "P1 · NOR")
        XCTAssertEqual(state.positionWindowStart, 4)
        XCTAssertEqual(state.positionDrivers?[2].positionChange, -1)
        XCTAssertEqual(state.positionDrivers?[0].positionChange, 1)
    }

    @MainActor
    func testActivityHelmetsAreDownsampledBeforeWidgetArchiving() throws {
        let source = IslandPreviewTexture.make(width: 685, height: 597) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 685, height: 597))
        }
        let image = try XCTUnwrap(ActivityHelmetImage.thumbnail(image: source))
        let pixels = try XCTUnwrap(image.cgImage)
        XCTAssertLessThanOrEqual(pixels.width, 180)
        XCTAssertLessThanOrEqual(pixels.height, 180)
    }

    func testBattleSelectionIsBoundedAndCanDeselect() {
        XCTAssertEqual(IslandBattleSelection.toggled("16", in: ["1", "4"]), ["1", "4"])
        XCTAssertEqual(IslandBattleSelection.toggled("1", in: ["1", "4"]), ["4"])
        XCTAssertEqual(IslandBattleSelection.toggled("16", in: ["4"]), ["4", "16"])
    }
    func testBattleDefaultsToFavoriteAndCarAheadOrP2() {
        func driver(_ number: String, _ position: Int, _ gap: String?, _ interval: String? = nil) -> LiveDriver {
            .init(number: number, name: number, team: nil, position: position, gap: gap, interval: interval, lapCount: nil, lastLap: nil, bestLap: nil)
        }
        let cars = [driver("4", 1, "LEADER"), driver("1", 2, "+0.842", "+0.842"), driver("16", 3, "+4.216", "+3.374")]
        XCTAssertEqual(IslandBattleSelection.drivers(in: cars, selected: [], favorite: cars[2]).map(\.number), ["1", "16"])
        XCTAssertEqual(IslandBattleSelection.drivers(in: cars, selected: [], favorite: cars[0]).map(\.number), ["4", "1"])
        XCTAssertEqual(IslandBattleSelection.drivers(in: cars, selected: ["16"], favorite: cars[0]).map(\.number), ["16"])
        XCTAssertEqual(IslandBattleSelection.gap(between: [cars[0], cars[2]]), "+4.216")
        XCTAssertEqual(IslandBattleSelection.gap(between: [driver("4", 1, nil), cars[2]]), "+4.216")
        XCTAssertEqual(IslandBattleSelection.gap(between: [cars[1], cars[2]]), "+3.374")
        XCTAssertNil(IslandBattleSelection.gap(between: [cars[0], driver("55", 5, "+1 LAP")]))
    }
    func testSingleSelectionCompactFollowsSelectedCarAndMissingBattleGapStaysUnknown() throws {
        var state = PitPulseActivityAttributes.ContentState(sessionName: "Race", meetingName: "GP", statusLabel: "Live", lapLabel: "L1/71", challengerGap: "+0.842", presentation: IslandContentMode.battle.rawValue, favoriteName: "Max VERSTAPPEN", favoritePosition: 2, battleDrivers: [.init(name: "Charles LECLERC", position: 3)])
        XCTAssertEqual(state.compactLeadingText, "LEC")
        XCTAssertEqual(state.compactTrailingText, "P3")
        state.battleDrivers?.append(.init(name: "Lewis HAMILTON", position: 4))
        XCTAssertEqual(state.compactTrailingText, "—")
        XCTAssertEqual(try JSONDecoder().decode(PitPulseActivityAttributes.ContentState.self, from: JSONEncoder().encode(state)), state)
    }

    func testActivityProgressRejectsUnavailableAndInvalidLapCounts() {
        var state = PitPulseActivityAttributes.ContentState(sessionName: "Race", meetingName: "São Paulo", statusLabel: "进行中", lapLabel: "L32/71")
        XCTAssertEqual(state.lapProgress ?? -1, 32.0 / 71, accuracy: 0.0001)
        for label in ["—", "L0/0", "L72/71", "L-1/71"] {
            state.lapLabel = label
            XCTAssertNil(state.lapProgress, label)
        }
        state.lapLabel = "L71/71"
        XCTAssertEqual(state.lapProgress, 1)
    }

    func testCompactContentFollowsSelectedViewingMode() {
        var state = PitPulseActivityAttributes.ContentState(sessionName: "Race", meetingName: "São Paulo", statusLabel: "进行中", lapLabel: "L32/71", challengerGap: "+0.842", favoriteName: "Max VERSTAPPEN", favoritePosition: 2)
        XCTAssertEqual(state.compactTrailingText, "L32/71")
        state.presentation = IslandContentMode.battle.rawValue
        XCTAssertEqual(state.compactTrailingText, "+0.842")
        state.presentation = IslandContentMode.favorite.rawValue
        XCTAssertEqual(state.compactLeadingText, "VER")
        XCTAssertEqual(state.compactTrailingText, "P2")
        state.favoritePosition = nil
        XCTAssertEqual(state.compactTrailingText, "—")
    }

    func testGapCaptionIsOptionalForExistingActivityPayloads() throws {
        let data = Data(#"{"sessionName":"Race","meetingName":"São Paulo","statusLabel":"进行中","lapLabel":"L32/71","driverCount":22,"isStale":false}"#.utf8)
        var state = try JSONDecoder().decode(PitPulseActivityAttributes.ContentState.self, from: data)
        XCTAssertNil(state.favoriteGapLabel)
        XCTAssertNil(state.weather)
        XCTAssertNil(state.positionDrivers)
        XCTAssertNil(state.positionFocus)
        XCTAssertNil(state.positionWindowStart)
        state.favoriteGapLabel = "距前车"
        state.weather = .init(rainfall: true, airTemperature: 24, trackTemperature: 37)
        let decoded = try JSONDecoder().decode(PitPulseActivityAttributes.ContentState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.favoriteGapLabel, "距前车")
        XCTAssertEqual(decoded.weather, state.weather)
        XCTAssertNil(decoded.weather?.visibilityMeters)
    }

    @MainActor
    func testPreviewMetalTextureUsesFixedRGBA8Pixels() throws {
        // Exercise the actual texture factory with grayscale drawing, which UIKit
        // previously promoted to @3x and then an unsupported monochrome format.
        let image = IslandPreviewTexture.make(width: 256, height: 4096) { context in
            UIColor(white: 0.65, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 4096))
        }
        let bitmap = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(bitmap.width, 256)
        XCTAssertEqual(bitmap.height, 4096)
        XCTAssertEqual(bitmap.bitsPerComponent, 8)
        XCTAssertEqual(bitmap.bitsPerPixel, 32)
        XCTAssertEqual(bitmap.colorSpace?.model, .rgb)
        XCTAssertEqual(image.scale, 1)
    }

    func testContentStateRoundTripsThroughJSON() throws {
        #if os(iOS)
        let state = PitPulseActivityAttributes.ContentState(
            sessionName: "Race",
            meetingName: "São Paulo Grand Prix",
            statusLabel: "进行中",
            lapLabel: "L32/71",
            leaderName: "Lando NORRIS",
            leaderGap: "LEADER",
            trackLabel: "绿旗 · 赛道畅通",
            driverCount: 22,
            isStale: false,
            updatedLabel: "刚刚",
            presentation: IslandContentMode.favorite.rawValue,
            favoriteName: "Lando Norris",
            favoritePosition: 1,
            favoriteGap: "LEADER",
            favoriteAsset: "helmet-norris-2026"
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PitPulseActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, state)
        #endif
    }

    func testWidgetCacheRoundTripAndClear() throws {
        let suite = "PitPulseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = RaceWidgetSnapshot(meeting: "Monza", session: "Race", start: Date(timeIntervalSince1970: 2000), savedAt: Date(timeIntervalSince1970: 1000))
        RaceWidgetCache.write(snapshot, to: defaults)
        XCTAssertEqual(RaceWidgetCache.read(from: defaults), snapshot)
        XCTAssertFalse(snapshot.isStale(at: Date(timeIntervalSince1970: 22600)))
        XCTAssertTrue(snapshot.isStale(at: Date(timeIntervalSince1970: 22601)))
        RaceWidgetCache.write(nil, to: defaults)
        XCTAssertNil(RaceWidgetCache.read(from: defaults))
        defaults.set(Data("invalid".utf8), forKey: RaceWidgetCache.key)
        XCTAssertNil(RaceWidgetCache.read(from: defaults))
    }

    func testOldActivityStateDecodesWithoutBattleFields() throws {
        let data = Data(#"{"sessionName":"Race","meetingName":"Monza","statusLabel":"replay","lapLabel":"L28/53","driverCount":20,"isStale":true}"#.utf8)
        let state = try JSONDecoder().decode(PitPulseActivityAttributes.ContentState.self, from: data)
        XCTAssertNil(state.challengerName)
        XCTAssertNil(state.leaderAsset)
        XCTAssertTrue(state.isStale)
        XCTAssertEqual(state.statusLabel, "replay")
    }

    func testChampionshipTrendGroupsSprintAndStopsAtMissingPoints() throws {
        let data = Data(#"{"rounds":[{"round":2,"entries":[{"points":25}]},{"round":1,"entries":[{"points":18}]},{"round":2,"entries":[{"points":8}]},{"round":3,"entries":[{}]},{"round":4,"entries":[{"points":25}]}],"warnings":[]}"#.utf8)
        let analysis = try JSONDecoder().decode(SeasonAnalysis.self, from: data)
        XCTAssertEqual(analysis.cumulativePointsByRound.map(\.round), [1, 2])
        XCTAssertEqual(analysis.cumulativePointsByRound.map(\.points), [18, 51])
    }

    func testLiveWidgetCachePreservesReplayAndExpires() throws {
        let suite = "PitPulseTimingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let time = Date(timeIntervalSince1970: 1000)
        let snapshot = RaceTimingSnapshot(meeting: "São Paulo", session: "Race", lap: "L28/71", status: "回放", updatedAt: time, stale: false,
            drivers: [RaceTimingDriver(id: "1", position: 1, name: "Lando Norris", gap: "LEADER", tire: "M", teamAsset: "team-logo-mclaren-2026")])
        RaceWidgetCache.writeTiming(snapshot, to: defaults)
        XCTAssertEqual(RaceWidgetCache.readTiming(from: defaults), snapshot)
        XCTAssertFalse(snapshot.isStale(at: time.addingTimeInterval(90)))
        XCTAssertTrue(snapshot.isStale(at: time.addingTimeInterval(91)))
        RaceWidgetCache.writeTiming(nil, to: defaults)
        XCTAssertNil(RaceWidgetCache.readTiming(from: defaults))
    }

    func testLegacyRaceWidgetSnapshotRemainsReadable() throws {
        let data = Data(#"{"meeting":"Monza","session":"FP1","start":1000,"savedAt":500}"#.utf8)
        let snapshot = try JSONDecoder().decode(RaceWidgetSnapshot.self, from: data)
        XCTAssertEqual(snapshot.meeting, "Monza")
        XCTAssertNil(snapshot.sessions)
        XCTAssertNil(snapshot.round)
    }

    func testRecordedTelemetryFractionalTimestampCanBeSampled() throws {
        let fractional = try XCTUnwrap(RFC3339.parse("2026-11-08T18:19:52.860000+00:00"))
        let whole = try XCTUnwrap(RFC3339.parse("2026-11-08T18:19:52Z"))
        XCTAssertEqual(fractional.timeIntervalSince(whole), 0.86, accuracy: 0.001)
    }

    func testAutomaticLiveSelectionTracksSingleAndConcurrentRaces() throws {
        let now = try XCTUnwrap(RFC3339.parse("2026-11-10T01:00:00Z"))
        let active = try liveFixture(status: "started", updatedAt: "2026-11-10T01:00:00Z")
        XCTAssertEqual(LiveSessionAvailability.selected(current: .f1, snapshots: [.wec: active], now: now), .wec)
        XCTAssertEqual(LiveSessionAvailability.selected(current: .wec, snapshots: [.f1: active, .wec: active], now: now), .wec)
        let finished = try liveFixture(status: "finished", updatedAt: "2026-11-10T01:00:00Z")
        XCTAssertEqual(LiveSessionAvailability.selected(current: .wec, snapshots: [.f1: active, .wec: finished], now: now), .f1)
    }

    func testAutomaticLiveSelectionRejectsFinishedInactiveAndOldRaces() throws {
        let now = try XCTUnwrap(RFC3339.parse("2026-11-10T01:00:00Z"))
        for status in ["finished", "inactive", "pending"] {
            XCTAssertFalse(LiveSessionAvailability.isAvailable(try liveFixture(status: status, updatedAt: "2026-11-10T01:00:00Z"), now: now))
        }
        XCTAssertFalse(LiveSessionAvailability.isAvailable(try liveFixture(status: "started", updatedAt: "2026-11-10T00:00:00Z"), now: now))
        XCTAssertFalse(LiveSessionAvailability.isAvailable(.disconnected(), now: now))
    }

    func testHelmetAssetsUseExistingDriverIdentityAliases() {
        XCTAssertEqual(MotorsportAssetName.helmetName(name: "Max VERSTAPPEN", season: 2026), "helmet-max_verstappen-2026")
        XCTAssertEqual(MotorsportAssetName.helmetName(name: "Rafael CÂMARA", season: 2026), "helmet-rafael_camara-2026")
        XCTAssertEqual(MotorsportAssetName.helmetName(driverID: "norris", name: "Lando Norris", season: 2026), "helmet-norris-2026")
    }

    private func liveFixture(status: String, updatedAt: String) throws -> LiveSnapshot {
        let json = """
        {"schemaVersion":1,"stateVersion":1,"sessionId":"race","sessionName":"Race","sourceStatus":"connected","sourceMode":"live","sessionStatus":"\(status)","updatedAt":"\(updatedAt)","drivers":[{"number":"1","position":1,"name":"Lando Norris"}],"raceControl":[]}
        """
        return try JSONDecoder().decode(LiveSnapshot.self, from: Data(json.utf8))
    }

    func testCalendarCountdownText() {
        XCTAssertEqual(CalendarLogic.countdownText(until: Date(), now: Date()), "不到 1 分钟")
    }

    func testLiveSnapshotDecodesActivityFields() throws {
        let json = """
        {"schemaVersion":1,"stateVersion":7,"sessionId":"2026:21:race","sessionName":"Race",
         "meetingName":"São Paulo Grand Prix","sourceStatus":"connected","sourceMode":"live",
         "statusReason":null,"sessionType":"Race","sessionStatus":"started","trackStatus":"AllClear",
         "lapCount":32,"totalLaps":71,"updatedAt":"2026-11-09T05:40:49Z","lastTransportAt":null,
         "drivers":[{"number":"1","name":"Lando NORRIS","position":1,"gap":"LEADER","lapCount":32}],
         "raceControl":[]}
        """
        let snapshot = try JSONDecoder().decode(LiveSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.lapLabel, "L32/71")
        XCTAssertEqual(snapshot.sessionStateLabel, "进行中")
        XCTAssertEqual(snapshot.drivers.first?.name, "Lando NORRIS")
    }
}
