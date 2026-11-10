import XCTest
@testable import PitPulseShared
@testable import PitPulseData

final class LiveActivityContentStateTests: XCTestCase {
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
