import Foundation
import WidgetKit
import PitPulseData
import PitPulseShared

/// App-only bridge. Extensions link Shared, never the networking/data module.
@MainActor
final class WidgetSnapshotPublisher {
    private let defaults: UserDefaults?
    private let reload: (String) -> Void
    private var lastLivePublish: Date?
    private var lastLiveIdentity: String?

    init(defaults: UserDefaults? = UserDefaults(suiteName: RaceWidgetCache.group),
         reload: @escaping (String) -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: $0) }) {
        self.defaults = defaults
        self.reload = reload
    }

    func publishCalendar(meetings: [Meeting], savedAt: Date, now: Date = .now) {
        let next = CalendarLogic.nextSession(in: meetings, now: now)
        let snapshot = next.map {
            RaceWidgetSnapshot(meeting: $0.meeting.name, session: $0.session.sessionType.displayName,
                start: $0.session.startTime, savedAt: savedAt, round: $0.meeting.round, location: $0.meeting.location,
                sessions: $0.meeting.sessions.filter { $0.status != .cancelled }.sorted { $0.startTime < $1.startTime }.map {
                    RaceWidgetSession(id: $0.id, title: $0.sessionType.displayName, start: $0.startTime)
                })
        }
        RaceWidgetCache.write(snapshot, to: defaults)
        reload(RaceWidgetCache.kind)
        reload(RaceWidgetCache.scheduleKind)
    }

    func publishLive(_ snapshot: LiveSnapshot, now: Date = .now) {
        guard !snapshot.isWec else { return }
        let identity = "\(snapshot.sessionId ?? "")|\(snapshot.statusLabel)"
        if let lastLivePublish, identity == lastLiveIdentity, now.timeIntervalSince(lastLivePublish) < 30 { return }
        lastLivePublish = now
        lastLiveIdentity = identity
        if snapshot.sessionId == nil {
            // A disconnect must never leave a fresh-looking timing cache behind.
            if var previous = RaceWidgetCache.readTiming(from: defaults) {
                previous.stale = true
                if !previous.status.contains("回放") { previous.status = snapshot.statusLabel }
                RaceWidgetCache.writeTiming(previous, to: defaults)
            }
        } else {
            RaceWidgetCache.writeTiming(RaceTimingSnapshot(
                meeting: snapshot.meetingName ?? "Formula 1", session: snapshot.sessionName ?? "—",
                lap: snapshot.lapLabel, status: snapshot.statusLabel,
                updatedAt: snapshot.updatedAt.flatMap(RFC3339.parse) ?? .distantPast,
                stale: snapshot.sourceStatus != .connected,
                drivers: snapshot.drivers.sorted { ($0.position ?? Int.max) < ($1.position ?? Int.max) }.prefix(8).map { driver in
                    RaceTimingDriver(id: driver.number, position: driver.position, name: driver.name ?? driver.number,
                        gap: driver.gap ?? driver.interval ?? "—", tire: driver.tireShortLabel,
                        teamAsset: LiveIslandLogic.teamAssetID(for: driver, isWec: false).map { "team-logo-\($0)-2026" })
                }), to: defaults)
        }
        reload(RaceWidgetCache.timingKind)
    }

    func clearLive() {
        lastLivePublish = nil
        lastLiveIdentity = nil
        RaceWidgetCache.writeTiming(nil, to: defaults)
        reload(RaceWidgetCache.timingKind)
    }

    func clear() {
        RaceWidgetCache.write(nil, to: defaults)
        reload(RaceWidgetCache.kind)
        reload(RaceWidgetCache.scheduleKind)
        clearLive()
    }
}
