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
