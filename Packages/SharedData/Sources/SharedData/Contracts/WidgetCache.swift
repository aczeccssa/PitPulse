import Foundation

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
