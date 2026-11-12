import Foundation

public struct FavoriteDriver: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum AppConnectionStatus: Equatable, Sendable {
    case idle, loading, connected, stale, offline, requiresToken, failed
}

public enum PreferenceKeys {
    public static let serverAddress = "serverAddress"
    public static let selectedSeason = "selectedSeason"
    public static let liveSeries = "liveSeries"
    public static let remindersEnabled = "remindersEnabled"
    public static let reminderMinutes = "reminderMinutes"
    public static let favoriteDriverId = "favoriteDriverId"
    public static let favoriteWecDriverId = "favoriteWecDriverId"
    public static let favoriteWecDriverName = "favoriteWecDriverName"
    public static let notchAutoShowEnabled = "notchAutoShowEnabled"
    public static let notchCollapseOnMouseExit = "notchCollapseOnMouseExit"
}

/// Compact state written by the host app and read by widget/watch extensions.
public struct WidgetContent: Codable, Equatable, Sendable {
    public var sessionName: String?
    public var meetingName: String?
    public var statusLabel: String?
    public var lapLabel: String?
    public var driverName: String?
    public var driverPosition: Int?
    public var series: String?
    public var updatedAt: String?
    public var isStale: Bool
    public init(sessionName: String? = nil, meetingName: String? = nil,
                statusLabel: String? = nil, lapLabel: String? = nil,
                driverName: String? = nil, driverPosition: Int? = nil,
                series: String? = nil, updatedAt: String? = nil,
                isStale: Bool = true) {
        self.sessionName = sessionName; self.meetingName = meetingName
        self.statusLabel = statusLabel; self.lapLabel = lapLabel
        self.driverName = driverName; self.driverPosition = driverPosition
        self.series = series; self.updatedAt = updatedAt
        self.isStale = isStale
    }
}

/// Asset naming rules usable from widgets without NSImage/UIImage.
public enum MotorsportAssetName {
    public enum Kind: Equatable, Sendable { case helmet, driverPhoto, teamLogo, carSide }
    public static func name(kind: Kind, id: String, season: Int) -> String {
        let prefix = switch kind {
        case .helmet: "helmet"
        case .driverPhoto: "driver-photo"
        case .teamLogo: "team-logo"
        case .carSide: "car-side"
        }
        let mapped = kind == .helmet
            ? ["verstappen": "max_verstappen", "lindblad": "arvid_lindblad"][id] ?? id
            : id
        return "\(prefix)-\(mapped)-\(season)"
    }
    public static func seriesLogoName(isWec: Bool) -> String {
        isWec ? "series-wec" : "series-f1"
    }
    public static func abbreviation(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        return String((parts.last ?? name.prefix(3)).prefix(3)).uppercased()
    }
}

/// The app publishes a token-free next-session cache. Widgets never contact providers.
public struct RaceWidgetSnapshot: Codable, Equatable, Sendable {
    public var meeting: String
    public var session: String
    public var start: Date
    public var savedAt: Date
    public var round: Int?
    public var location: String?
    public var sessions: [RaceWidgetSession]?
    public init(meeting: String, session: String, start: Date, savedAt: Date = .now,
                round: Int? = nil, location: String? = nil, sessions: [RaceWidgetSession]? = nil) {
        self.meeting = meeting; self.session = session; self.start = start; self.savedAt = savedAt
        self.round = round; self.location = location; self.sessions = sessions
    }
    public func isStale(at date: Date) -> Bool { date.timeIntervalSince(savedAt) > 3600 * 6 }
}

/// Only the two widget destinations are accepted; no arbitrary URL dispatch.
public enum WidgetDestination: String, Sendable {
    case calendar, live

    public init?(url: URL) {
        guard ["pitpulse", "pitpulse-desktop"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              url.path.isEmpty || url.path == "/",
              let host = url.host, let destination = Self(rawValue: host) else { return nil }
        self = destination
    }

    public var url: URL {
        #if os(macOS)
        URL(string: "pitpulse-desktop://\(rawValue)")!
        #else
        URL(string: "pitpulse://\(rawValue)")!
        #endif
    }
}

public enum RaceWidgetCache {
    #if os(macOS)
    // A Team-prefixed Mac group works without new iOS-style provisioning profiles.
    public static let group = "9RQST8G2LS.com.pitpulse.widgets"
    #else
    public static let group = "group.com.pitpulse.mobile"
    #endif
    public static let kind = "PitPulseRaceWeekend"
    public static let key = "raceWeekendSnapshot"
    public static func read(from defaults: UserDefaults? = UserDefaults(suiteName: group)) -> RaceWidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RaceWidgetSnapshot.self, from: data)
    }
    public static func write(_ snapshot: RaceWidgetSnapshot?, to defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) { defaults?.set(data, forKey: key) }
        else { defaults?.removeObject(forKey: key) }
    }
}


public struct RaceWidgetSession: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public init(id: String, title: String, start: Date) { self.id = id; self.title = title; self.start = start }
}

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

extension RaceWidgetCache {
    public static let scheduleKind = "PitPulseWeekendSchedule"
    public static let timingKind = "PitPulseLiveTiming"
    public static let timingKey = "liveTimingSnapshot"
    public static func readTiming(from defaults: UserDefaults? = UserDefaults(suiteName: group)) -> RaceTimingSnapshot? {
        guard let data = defaults?.data(forKey: timingKey) else { return nil }
        return try? JSONDecoder().decode(RaceTimingSnapshot.self, from: data)
    }
    public static func writeTiming(_ snapshot: RaceTimingSnapshot?, to defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) { defaults?.set(data, forKey: timingKey) }
        else { defaults?.removeObject(forKey: timingKey) }
    }
}

// MARK: - Standings widget

public struct WidgetStandingDriver: Codable, Equatable, Sendable, Identifiable {
    public var id: String { driverID }
    public var driverID: String
    public var name: String
    public var team: String
    public var constructorID: String?
    public var position: Int
    public var points: Double
    public var gapToLeader: Double
    public init(driverID: String, name: String, team: String, constructorID: String? = nil,
                position: Int, points: Double, gapToLeader: Double) {
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

// MARK: - Last race widget

public struct LastRacePodiumEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { driverID }
    public var driverID: String
    public var name: String
    public var team: String
    public var constructorID: String?
    public var position: Int
    public var time: String
    public var points: Double?
    public init(driverID: String, name: String, team: String, constructorID: String? = nil,
                position: Int, time: String, points: Double? = nil) {
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
    public init(id: String, round: Int? = nil, name: String, location: String,
                countryCode: String? = nil, start: Date, end: Date, raceStart: Date? = nil,
                nextSessionStart: Date? = nil, nextSessionTitle: String? = nil) {
        self.id = id; self.round = round; self.name = name; self.location = location
        self.countryCode = countryCode; self.start = start; self.end = end; self.raceStart = raceStart
        self.nextSessionStart = nextSessionStart; self.nextSessionTitle = nextSessionTitle
    }
}

public struct UpcomingWidgetSnapshot: Codable, Equatable, Sendable {
    public var savedAt: Date
    public var races: [UpcomingRaceEntry]
    public init(savedAt: Date = .now, races: [UpcomingRaceEntry]) {
        self.savedAt = savedAt; self.races = races
    }
    public func isStale(at date: Date) -> Bool { date.timeIntervalSince(savedAt) > 3600 * 6 }
}

extension RaceWidgetCache {
    public static let standingsKind = "PitPulseStandings"
    public static let standingsKey = "standingsWidgetSnapshot"
    public static let lastRaceKind = "PitPulseLastRace"
    public static let lastRaceKey = "lastRaceWidgetSnapshot"
    public static let upcomingKind = "PitPulseUpcoming"
    public static let upcomingKey = "upcomingWidgetSnapshot"
    public static let favoriteDriverKind = "PitPulseFavoriteDriver"
    public static let favoriteDriverKey = "favoriteDriverWidgetSnapshot"

    public static func readStandings(from defaults: UserDefaults? = UserDefaults(suiteName: group)) -> StandingsWidgetSnapshot? {
        guard let data = defaults?.data(forKey: standingsKey) else { return nil }
        return try? JSONDecoder().decode(StandingsWidgetSnapshot.self, from: data)
    }
    public static func writeStandings(_ snapshot: StandingsWidgetSnapshot?, to defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) { defaults?.set(data, forKey: standingsKey) }
        else { defaults?.removeObject(forKey: standingsKey) }
    }
    public static func readLastRace(from defaults: UserDefaults? = UserDefaults(suiteName: group)) -> LastRaceWidgetSnapshot? {
        guard let data = defaults?.data(forKey: lastRaceKey) else { return nil }
        return try? JSONDecoder().decode(LastRaceWidgetSnapshot.self, from: data)
    }
    public static func writeLastRace(_ snapshot: LastRaceWidgetSnapshot?, to defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) { defaults?.set(data, forKey: lastRaceKey) }
        else { defaults?.removeObject(forKey: lastRaceKey) }
    }
    public static func readUpcoming(from defaults: UserDefaults? = UserDefaults(suiteName: group)) -> UpcomingWidgetSnapshot? {
        guard let data = defaults?.data(forKey: upcomingKey) else { return nil }
        return try? JSONDecoder().decode(UpcomingWidgetSnapshot.self, from: data)
    }
    public static func writeUpcoming(_ snapshot: UpcomingWidgetSnapshot?, to defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) { defaults?.set(data, forKey: upcomingKey) }
        else { defaults?.removeObject(forKey: upcomingKey) }
    }
    public static func readFavoriteDriver(from defaults: UserDefaults? = UserDefaults(suiteName: group)) -> FavoriteDriverWidgetSnapshot? {
        guard let data = defaults?.data(forKey: favoriteDriverKey) else { return nil }
        return try? JSONDecoder().decode(FavoriteDriverWidgetSnapshot.self, from: data)
    }
    public static func writeFavoriteDriver(_ snapshot: FavoriteDriverWidgetSnapshot?, to defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) { defaults?.set(data, forKey: favoriteDriverKey) }
        else { defaults?.removeObject(forKey: favoriteDriverKey) }
    }
}


public enum IslandContentMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case overview, battle, favorite, positionChanges
    public var id: String { rawValue }
    public var title: String {
        switch self { case .overview: "赛事脉搏"; case .battle: "领跑之争"; case .favorite: "我的车手"; case .positionChanges: "全场风云" }
    }
}

extension MotorsportAssetName {
    public static func helmetName(driverID: String? = nil, name: String, season: Int) -> String {
        let surname = String(name.split(whereSeparator: \.isWhitespace).last ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let id = driverID ?? ["camara": "rafael_camara"][surname] ?? surname
        return self.name(kind: .helmet, id: id, season: season)
    }
}
