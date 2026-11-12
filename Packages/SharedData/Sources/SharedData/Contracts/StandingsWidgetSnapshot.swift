import Foundation

// MARK: - Standings widget

public struct WidgetStandingDriver: Codable, Equatable, Sendable, Identifiable {
    public var id: String { driverID }
    public var driverID: String
    public var driverNumber: String?
    public var name: String
    public var team: String
    public var constructorID: String?
    public var position: Int
    public var points: Double
    public var gapToLeader: Double
    public init(driverID: String, name: String, team: String, constructorID: String? = nil,
                position: Int, points: Double, gapToLeader: Double, driverNumber: String? = nil) {
        self.driverNumber = driverNumber
        self.driverID = driverID; self.name = name; self.team = team
        self.constructorID = constructorID; self.position = position
        self.points = points; self.gapToLeader = gapToLeader
    }
}

public struct StandingsWidgetSnapshot: Codable, Equatable, Sendable {
    public var season: Int
    public var savedAt: Date
    public var drivers: [WidgetStandingDriver]
    public init(season: Int, savedAt: Date = .now, drivers: [WidgetStandingDriver]) {
        self.season = season; self.savedAt = savedAt; self.drivers = drivers
    }
    public func isStale(at date: Date) -> Bool { date.timeIntervalSince(savedAt) > 3600 * 6 }
}
