import Foundation

// MARK: - Upcoming races widget

public struct UpcomingRaceEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var round: Int?
    public var name: String
    public var location: String
    public var countryCode: String?
    public var start: Date
    public var end: Date
    public var raceStart: Date?
    public var nextSessionStart: Date?
    public var nextSessionTitle: String?
    public var sessions: [RaceWidgetSession]?
    public init(id: String, round: Int? = nil, name: String, location: String,
                countryCode: String? = nil, start: Date, end: Date, raceStart: Date? = nil,
                nextSessionStart: Date? = nil, nextSessionTitle: String? = nil, sessions: [RaceWidgetSession]? = nil) {
        self.id = id; self.round = round; self.name = name; self.location = location
        self.countryCode = countryCode; self.start = start; self.end = end; self.raceStart = raceStart
        self.nextSessionStart = nextSessionStart; self.nextSessionTitle = nextSessionTitle
        self.sessions = sessions
    }
}

public struct UpcomingWidgetSnapshot: Codable, Equatable, Sendable {
    public var savedAt: Date
    public var races: [UpcomingRaceEntry]
    public init(savedAt: Date = .now, races: [UpcomingRaceEntry]) {
        self.savedAt = savedAt; self.races = races
    }
    public func remaining(at date: Date) -> UpcomingWidgetSnapshot? {
        var copy = self
        copy.races = races.filter { $0.end >= date }.sorted { $0.start < $1.start }.map { race in
            var race = race
            if let sessions = race.sessions {
                let next = sessions.filter { $0.start >= date }.min { $0.start < $1.start }
                race.nextSessionStart = next?.start
                race.nextSessionTitle = next?.title
            } else if let start = race.nextSessionStart, start < date {
                race.nextSessionStart = nil
                race.nextSessionTitle = nil
            }
            return race
        }
        return copy.races.isEmpty ? nil : copy
    }

    public func nextSession(at date: Date) -> RaceWidgetSnapshot? {
        races.filter { $0.end >= date }.compactMap { race -> RaceWidgetSnapshot? in
            let next = race.sessions?.filter { $0.start >= date }.min { $0.start < $1.start }
            guard let start = next?.start ?? race.nextSessionStart, start >= date,
                  let title = next?.title ?? race.nextSessionTitle else { return nil }
            return RaceWidgetSnapshot(meeting: race.name, session: title, start: start, savedAt: savedAt,
                round: race.round, location: race.location, sessions: race.sessions)
        }.min { $0.start < $1.start }
    }

    public func isStale(at date: Date) -> Bool { date.timeIntervalSince(savedAt) > 3600 * 6 }
}
