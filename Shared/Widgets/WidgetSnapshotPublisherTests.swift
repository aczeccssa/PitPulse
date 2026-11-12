import Foundation
import XCTest
import PitPulseData
import PitPulseShared
#if os(macOS) && !WIDGET_STANDALONE
@testable import PitPulseDesktop
#endif

@MainActor
final class WidgetSnapshotPublisherTests: XCTestCase {
    private func isolated(_ body: (UserDefaults, WidgetSnapshotPublisher, () -> [String]) throws -> Void) throws {
        let suite = "PitPulseWidgetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var reloads: [String] = []
        let publisher = WidgetSnapshotPublisher(defaults: defaults, reload: { reloads.append($0) })
        try body(defaults, publisher, { reloads })
    }

    func testCalendarPreservesOriginalAgeFiltersCancelledAndClearsEmpty() throws {
        try isolated { defaults, publisher, reloads in
            let now = Date(timeIntervalSince1970: 1000)
            let session = Session(id: "fp1", meetingId: "m", sessionType: .fp1, startTime: now.addingTimeInterval(3600),
                endTime: nil, status: .scheduled, jolpicaSessionId: nil, openf1SessionKey: nil)
            let cancelled = Session(id: "race", meetingId: "m", sessionType: .race, startTime: now.addingTimeInterval(7200),
                endTime: nil, status: .cancelled, jolpicaSessionId: nil, openf1SessionKey: nil)
            let meeting = Meeting(id: "m", season: 2026, round: 1, name: "Fixture GP", country: "Australia", countryCode: "AU",
                location: "Melbourne", startDate: now, endDate: now.addingTimeInterval(8000), status: .scheduled,
                sessions: [cancelled, session], source: "fixture", fetchedAt: now, sourceUpdatedAt: nil, revision: 1)
            let saved = now.addingTimeInterval(-30000)
            publisher.publishCalendar(meetings: [meeting], savedAt: saved, now: now)
            let snapshot = try XCTUnwrap(RaceWidgetCache.read(from: defaults))
            XCTAssertEqual(snapshot.savedAt, saved)
            XCTAssertTrue(snapshot.isStale(at: now))
            XCTAssertEqual(snapshot.sessions?.map(\.id), ["fp1"])
            XCTAssertEqual(snapshot.meeting, "Fixture GP")
            XCTAssertEqual(reloads(), [RaceWidgetCache.kind, RaceWidgetCache.scheduleKind, RaceWidgetCache.upcomingKind])
            let upcoming = try XCTUnwrap(RaceWidgetCache.readUpcoming(from: defaults))
            XCTAssertEqual(upcoming.races.map(\.round), [1])
            XCTAssertEqual(upcoming.races.first?.nextSessionTitle, "FP1")
            publisher.publishCalendar(meetings: [], savedAt: now, now: now)
            XCTAssertNil(RaceWidgetCache.read(from: defaults))
            XCTAssertNil(RaceWidgetCache.readUpcoming(from: defaults))
        }
    }

    func testStandingsPublishesTopFiveAndGapToLeader() throws {
        try isolated { defaults, publisher, reloads in
            let standings = try fixtureStandings()
            let saved = Date(timeIntervalSince1970: 1000)
            publisher.publishStandings(standings, season: 2026, savedAt: saved)
            let snapshot = try XCTUnwrap(RaceWidgetCache.readStandings(from: defaults))
            XCTAssertEqual(snapshot.drivers.count, 5)
            XCTAssertEqual(snapshot.drivers.first?.points, 390)
            XCTAssertEqual(snapshot.drivers.map(\.gapToLeader), [0, 111, 128, 141, 176])
            XCTAssertEqual(reloads(), [RaceWidgetCache.standingsKind])
            publisher.clear()
            XCTAssertNil(RaceWidgetCache.readStandings(from: defaults))
        }
    }

    func testFavoriteDriverPublishesGapAndClearsWithoutSelection() throws {
        try isolated { defaults, publisher, reloads in
            let standings = try fixtureStandings()
            let saved = Date(timeIntervalSince1970: 1000)
            publisher.publishFavoriteDriver(standings, favoriteID: "leclerc", season: 2026, savedAt: saved)
            let snapshot = try XCTUnwrap(RaceWidgetCache.readFavoriteDriver(from: defaults))
            XCTAssertEqual(snapshot.driver.position, 4)
            XCTAssertEqual(snapshot.driver.points, 249)
            XCTAssertEqual(snapshot.driver.gapToLeader, 141)
            XCTAssertEqual(snapshot.gapToBehind, 35)
            XCTAssertEqual(snapshot.wins, 1)
            XCTAssertTrue(snapshot.recentRaces.isEmpty)
            XCTAssertEqual(reloads(), [RaceWidgetCache.favoriteDriverKind])
            publisher.publishFavoriteDriver(standings, favoriteID: "unknown", season: 2026, savedAt: saved)
            XCTAssertNil(RaceWidgetCache.readFavoriteDriver(from: defaults))
            publisher.publishFavoriteDriver(standings, favoriteID: "leclerc", season: 2026, savedAt: saved)
            publisher.clear()
            XCTAssertNil(RaceWidgetCache.readFavoriteDriver(from: defaults))
        }
    }

    func testFavoriteDriverPublishesRecentRaceForm() throws {
        try isolated { defaults, publisher, _ in
            let standings = try fixtureStandings()
            let now = Date(timeIntervalSince1970: 1000)
            let session = Session(id: "race20", meetingId: "m20", sessionType: .race, startTime: now,
                endTime: nil, status: .finished, jolpicaSessionId: nil, openf1SessionKey: nil)
            let meeting = Meeting(id: "m20", season: 2026, round: 20, name: "São Paulo Grand Prix",
                country: "Brazil", countryCode: "BR", location: "São Paulo",
                startDate: now.addingTimeInterval(-7200), endDate: now.addingTimeInterval(7200),
                status: .scheduled, sessions: [session], source: "fixture", fetchedAt: now,
                sourceUpdatedAt: nil, revision: 1)
            let results = try JSONDecoder().decode([SessionResult].self, from: Data("""
            [{"sessionId":"race20","position":4,"classification":"CLASSIFIED","driverId":"leclerc","driverName":"Charles Leclerc","constructorId":"ferrari","team":"Ferrari","gap":"+12.345","bestLap":"1:12.486","laps":71,"points":12,"source":"fixture","fetchedAt":0,"revision":1,"quality":"final"}]
            """.utf8))
            let source = FavoriteRaceSource(meeting: meeting, session: session, results: results, savedAt: now)
            publisher.publishFavoriteDriver(standings, favoriteID: "leclerc", season: 2026,
                savedAt: now, recentRaces: [source])
            let snapshot = try XCTUnwrap(RaceWidgetCache.readFavoriteDriver(from: defaults))
            XCTAssertEqual(snapshot.recentRaces.count, 1)
            let race = try XCTUnwrap(snapshot.recentRaces.first)
            XCTAssertEqual(race.round, 20)
            XCTAssertEqual(race.meeting, "São Paulo Grand Prix")
            XCTAssertEqual(race.position, 4)
            XCTAssertEqual(race.points, 12)
            XCTAssertEqual(race.laps, 71)
            XCTAssertEqual(race.fastestLap, "1:12.486")
            XCTAssertEqual(race.gap, "+12.345")
            XCTAssertEqual(race.classification, "已分类")
        }
    }

    func testLastRacePublishesPodiumTimesFastestLapAndLaps() throws {
        try isolated { defaults, publisher, reloads in
            let now = Date(timeIntervalSince1970: 1000)
            let session = Session(id: "race", meetingId: "m", sessionType: .race, startTime: now,
                endTime: nil, status: .finished, jolpicaSessionId: nil, openf1SessionKey: nil)
            let meeting = Meeting(id: "m", season: 2026, round: 20, name: "São Paulo Grand Prix", country: "Brazil",
                countryCode: "BR", location: "São Paulo", startDate: now.addingTimeInterval(-7200),
                endDate: now.addingTimeInterval(7200), status: .scheduled, sessions: [session],
                source: "fixture", fetchedAt: now, sourceUpdatedAt: nil, revision: 1)
            let results = try JSONDecoder().decode([SessionResult].self, from: Data("""
            [{"sessionId":"race","position":1,"classification":"CLASSIFIED","driverId":"antonelli","driverName":"Andrea Kimi Antonelli","constructorId":"mercedes","team":"Mercedes","raceTime":"1:32:45.678","bestLap":"1:12.486","laps":71,"points":25,"source":"fixture","fetchedAt":0,"revision":1,"quality":"final"},
             {"sessionId":"race","position":2,"classification":"CLASSIFIED","driverId":"verstappen","driverName":"Max Verstappen","constructorId":"red_bull","team":"Red Bull Racing","gap":"+2.145","bestLap":"1:11.900","laps":71,"points":18,"source":"fixture","fetchedAt":0,"revision":1,"quality":"final"},
             {"sessionId":"race","position":3,"classification":"CLASSIFIED","driverId":"russell","driverName":"George Russell","constructorId":"mercedes","team":"Mercedes","gap":"+8.902","bestLap":"1:12.771","laps":71,"points":15,"source":"fixture","fetchedAt":0,"revision":1,"quality":"final"}]
            """.utf8))
            publisher.publishLastRace(meeting: meeting, session: session, results: results, savedAt: now)
            let snapshot = try XCTUnwrap(RaceWidgetCache.readLastRace(from: defaults))
            XCTAssertEqual(snapshot.podium.map(\.position), [1, 2, 3])
            XCTAssertEqual(snapshot.podium.first?.time, "1:32:45.678")
            XCTAssertEqual(snapshot.podium[1].time, "+2.145")
            XCTAssertEqual(snapshot.fastestLap, "1:11.900")
            XCTAssertEqual(snapshot.laps, 71)
            XCTAssertEqual(snapshot.round, 20)
            XCTAssertEqual(reloads(), [RaceWidgetCache.lastRaceKind])
        }
    }

    func testLiveThrottleStatusAndSessionChangesBypassBudget() throws {
        try isolated { defaults, publisher, reloads in
            let now = Date(timeIntervalSince1970: 1000)
            publisher.publishLive(try live(id: "one", lap: 1), now: now)
            publisher.publishLive(try live(id: "one", lap: 2), now: now.addingTimeInterval(10))
            XCTAssertEqual(RaceWidgetCache.readTiming(from: defaults)?.lap, "L1")
            publisher.publishLive(try live(id: "one", lap: 3), now: now.addingTimeInterval(30))
            XCTAssertEqual(RaceWidgetCache.readTiming(from: defaults)?.lap, "L3")
            publisher.publishLive(try live(id: "two", lap: 4), now: now.addingTimeInterval(31))
            XCTAssertEqual(RaceWidgetCache.readTiming(from: defaults)?.lap, "L4")
            publisher.publishLive(try live(id: "two", lap: 5, status: "stale"), now: now.addingTimeInterval(32))
            XCTAssertTrue(try XCTUnwrap(RaceWidgetCache.readTiming(from: defaults)).stale)
            XCTAssertEqual(reloads().count, 4)
        }
    }

    func testReplayDisconnectMissingTimestampAndWecCannotLookLive() throws {
        try isolated { defaults, publisher, _ in
            let now = Date(timeIntervalSince1970: 1000)
            publisher.publishLive(try live(id: "one", lap: 1, mode: "replay"), now: now)
            XCTAssertEqual(RaceWidgetCache.readTiming(from: defaults)?.status, "回放")
            publisher.publishLive(.disconnected(), now: now.addingTimeInterval(1))
            let disconnected = try XCTUnwrap(RaceWidgetCache.readTiming(from: defaults))
            XCTAssertTrue(disconnected.stale)
            XCTAssertEqual(disconnected.status, "回放")
            publisher.publishLive(try live(id: "wec", lap: 9, series: "wec"), now: now.addingTimeInterval(31))
            XCTAssertEqual(RaceWidgetCache.readTiming(from: defaults), disconnected)
            publisher.clearLive()
            XCTAssertNil(RaceWidgetCache.readTiming(from: defaults))
            publisher.publishLive(try live(id: "new", lap: 1, timestamp: false), now: now.addingTimeInterval(32))
            XCTAssertTrue(try XCTUnwrap(RaceWidgetCache.readTiming(from: defaults)).isStale(at: now))
            publisher.clear()
            XCTAssertNil(RaceWidgetCache.readTiming(from: defaults))
            XCTAssertNil(RaceWidgetCache.read(from: defaults))
        }
    }

    func testWidgetDestinationOnlyAcceptsKnownRoutes() throws {
        XCTAssertEqual(WidgetDestination(url: try XCTUnwrap(URL(string: "pitpulse-desktop://calendar"))), .calendar)
        XCTAssertEqual(WidgetDestination(url: try XCTUnwrap(URL(string: "pitpulse://live?series=f1"))), .live)
        for text in ["https://calendar", "pitpulse://settings", "pitpulse-desktop://live/arbitrary", "pitpulse://user@live"] {
            XCTAssertNil(WidgetDestination(url: try XCTUnwrap(URL(string: text))))
        }
        #if os(macOS)
        XCTAssertEqual(WidgetDestination.live.url.scheme, "pitpulse-desktop")
        #else
        XCTAssertEqual(WidgetDestination.live.url.scheme, "pitpulse")
        #endif
    }

    private func fixtureStandings() throws -> [DriverStanding] {
        try JSONDecoder().decode([DriverStanding].self, from: Data("""
        [{"season":2026,"position":1,"driverId":"antonelli","driverName":"Andrea Kimi Antonelli","constructor":"Mercedes","constructorIds":["mercedes"],"points":390,"wins":7,"source":"fixture","fetchedAt":0,"revision":1},
         {"season":2026,"position":2,"driverId":"verstappen","driverName":"Max Verstappen","constructor":"Red Bull Racing","constructorIds":["red_bull"],"points":279,"wins":4,"source":"fixture","fetchedAt":0,"revision":1},
         {"season":2026,"position":3,"driverId":"russell","driverName":"George Russell","constructor":"Mercedes","constructorIds":["mercedes"],"points":262,"wins":2,"source":"fixture","fetchedAt":0,"revision":1},
         {"season":2026,"position":4,"driverId":"leclerc","driverName":"Charles Leclerc","constructor":"Ferrari","constructorIds":["ferrari"],"points":249,"wins":1,"source":"fixture","fetchedAt":0,"revision":1},
         {"season":2026,"position":5,"driverId":"hamilton","driverName":"Lewis Hamilton","constructor":"Ferrari","constructorIds":["ferrari"],"points":214,"wins":0,"source":"fixture","fetchedAt":0,"revision":1},
         {"season":2026,"position":6,"driverId":"norris","driverName":"Lando Norris","constructor":"McLaren","constructorIds":["mclaren"],"points":199,"wins":0,"source":"fixture","fetchedAt":0,"revision":1}]
        """.utf8))
    }

    private func live(id: String, lap: Int, status: String = "connected", mode: String = "live",
                      series: String = "f1", timestamp: Bool = true) throws -> LiveSnapshot {
        let object: [String: Any] = ["schemaVersion": 1, "stateVersion": lap, "sessionId": id, "sessionName": "Race",
            "series": series, "sourceStatus": status, "sourceMode": mode, "lapCount": lap,
            "updatedAt": timestamp ? "2026-11-10T01:00:00Z" as Any : NSNull(), "drivers": []]
        return try JSONDecoder().decode(LiveSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
