import Foundation

// MARK: - Last race widget

public struct LastRacePodiumEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { driverID }
    public var driverID: String
    public var driverNumber: String?
    public var name: String
    public var team: String
    public var constructorID: String?
    public var position: Int
    public var time: String
    public var points: Double?
    public init(driverID: String, name: String, team: String, constructorID: String? = nil,
                position: Int, time: String, points: Double? = nil, driverNumber: String? = nil) {
        self.driverNumber = driverNumber
        self.driverID = driverID; self.name = name; self.team = team
        self.constructorID = constructorID; self.position = position
        self.time = time; self.points = points
    }
}

public struct LastRaceWidgetSnapshot: Codable, Equatable, Sendable {
    public var meeting: String
    public var session: String
    public var season: Int?
    public var round: Int?
    public var raceDate: Date?
    public var savedAt: Date
    public var podium: [LastRacePodiumEntry]
    public var fastestLap: String?
    public var laps: Int?
    public var safetyCars: Int?
    public init(meeting: String, session: String, season: Int? = nil, round: Int? = nil,
                raceDate: Date? = nil, savedAt: Date = .now, podium: [LastRacePodiumEntry],
                fastestLap: String? = nil, laps: Int? = nil, safetyCars: Int? = nil) {
        self.meeting = meeting; self.session = session; self.season = season
        self.round = round; self.raceDate = raceDate
        self.savedAt = savedAt; self.podium = podium; self.fastestLap = fastestLap
        self.laps = laps; self.safetyCars = safetyCars
    }
    public func isStale(at date: Date) -> Bool { date.timeIntervalSince(savedAt) > 3600 * 6 }
}
