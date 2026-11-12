import Foundation

// MARK: - Favorite driver widget

public struct FavoriteRaceEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var round: Int?
    public var meeting: String
    public var date: Date
    public var position: Int?
    public var points: Double?
    public var laps: Int?
    public var fastestLap: String?
    public var gap: String?
    public var classification: String?
    public init(id: String, round: Int? = nil, meeting: String, date: Date, position: Int? = nil,
                points: Double? = nil, laps: Int? = nil, fastestLap: String? = nil,
                gap: String? = nil, classification: String? = nil) {
        self.id = id; self.round = round; self.meeting = meeting; self.date = date
        self.position = position; self.points = points; self.laps = laps
        self.fastestLap = fastestLap; self.gap = gap; self.classification = classification
    }
}

public struct FavoriteDriverWidgetSnapshot: Codable, Equatable, Sendable {
    public var season: Int
    public var savedAt: Date
    public var favoriteID: String
    public var driver: WidgetStandingDriver
    public var wins: Int
    /// Points advantage over the next driver, used when the favorite leads the championship.
    public var gapToBehind: Double?
    /// Most recent completed races, newest first.
    public var recentRaces: [FavoriteRaceEntry]
    public init(season: Int, savedAt: Date = .now, favoriteID: String, driver: WidgetStandingDriver,
                wins: Int = 0, gapToBehind: Double? = nil, recentRaces: [FavoriteRaceEntry] = []) {
        self.season = season; self.savedAt = savedAt; self.favoriteID = favoriteID
        self.driver = driver; self.wins = wins; self.gapToBehind = gapToBehind
        self.recentRaces = recentRaces
    }
    public func isStale(at date: Date) -> Bool { date.timeIntervalSince(savedAt) > 3600 * 6 }
}
