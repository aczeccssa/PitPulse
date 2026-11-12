import Foundation

public enum LiveSessionAvailability {
    public static func isAvailable(_ snapshot: LiveSnapshot, now: Date = .now) -> Bool {
        guard snapshot.sessionId != nil, snapshot.sourceStatus != .disconnected,
              !snapshot.drivers.isEmpty,
              ["started", "running", "live", "suspended"].contains(snapshot.sessionStatus?.lowercased() ?? ""),
              LiveFreshness.isFresh(snapshot.updatedAt, now: now, maximumAge: 90) else { return false }
        return true
    }

    public static func selected(current: LiveSeries, snapshots: [LiveSeries: LiveSnapshot], now: Date = .now) -> LiveSeries? {
        let available = LiveSeries.allCases.filter { snapshots[$0].map { isAvailable($0, now: now) } ?? false }
        return available.contains(current) ? current : available.first
    }
}
