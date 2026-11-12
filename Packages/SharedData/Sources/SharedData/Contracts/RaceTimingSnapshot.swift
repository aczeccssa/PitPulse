import Foundation

public struct RaceTimingDriver: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var position: Int?
    public var name: String
    public var gap: String
    public var tire: String?
    public var teamAsset: String?
    public init(id: String, position: Int?, name: String, gap: String, tire: String? = nil, teamAsset: String? = nil) {
        self.id = id; self.position = position; self.name = name; self.gap = gap; self.tire = tire; self.teamAsset = teamAsset
    }
}

public struct RaceTimingSnapshot: Codable, Equatable, Sendable {
    public var meeting: String
    public var session: String
    public var lap: String
    public var status: String
    public var updatedAt: Date
    public var stale: Bool
    public var drivers: [RaceTimingDriver]
    public init(meeting: String, session: String, lap: String, status: String, updatedAt: Date, stale: Bool, drivers: [RaceTimingDriver]) {
        self.meeting = meeting; self.session = session; self.lap = lap; self.status = status
        self.updatedAt = updatedAt; self.stale = stale; self.drivers = drivers
    }
    public func isStale(at date: Date) -> Bool { stale || date.timeIntervalSince(updatedAt) > 90 }
}
