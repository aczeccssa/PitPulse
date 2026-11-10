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

public enum RaceWidgetCache {
    public static let group = "group.com.pitpulse.mobile"
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


public enum IslandContentMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case overview, battle, favorite
    public var id: String { rawValue }
    public var title: String {
        switch self { case .overview: "赛事总览"; case .battle: "前排对比"; case .favorite: "喜欢的车手" }
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
