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
