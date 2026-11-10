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
            XCTAssertEqual(reloads(), [RaceWidgetCache.kind, RaceWidgetCache.scheduleKind])
            publisher.publishCalendar(meetings: [], savedAt: now, now: now)
            XCTAssertNil(RaceWidgetCache.read(from: defaults))
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

    private func live(id: String, lap: Int, status: String = "connected", mode: String = "live",
                      series: String = "f1", timestamp: Bool = true) throws -> LiveSnapshot {
        let object: [String: Any] = ["schemaVersion": 1, "stateVersion": lap, "sessionId": id, "sessionName": "Race",
            "series": series, "sourceStatus": status, "sourceMode": mode, "lapCount": lap,
            "updatedAt": timestamp ? "2026-11-10T01:00:00Z" as Any : NSNull(), "drivers": []]
        return try JSONDecoder().decode(LiveSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
