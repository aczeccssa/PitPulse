import Foundation

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
    /// PitPulse brand mark from the shared asset catalog.
    public static let brandLogoName = "logo-foreground"
    public static func abbreviation(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        return String((parts.last ?? name.prefix(3)).prefix(3)).uppercased()
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
