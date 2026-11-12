import Foundation

public enum LiveFreshness {
    public static func age(_ utc: String?, now: Date = Date()) -> TimeInterval? {
        guard let utc, let date = RFC3339.parse(utc) else { return nil }
        return now.timeIntervalSince(date)
    }

    public static func isFresh(_ utc: String?, now: Date = Date(), maximumAge: TimeInterval = 10) -> Bool {
        guard let age = age(utc, now: now) else { return false }
        return age >= -5 && age <= maximumAge
    }
}
