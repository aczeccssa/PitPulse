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
        let mapped = canonicalID(kind: kind, id: id)
        return "\(prefix)-\(mapped)-\(season)"
    }
    public static func canonicalID(kind: Kind, id: String) -> String {
        let slug = LiveIslandLogic.assetSlug(id).replacingOccurrences(of: "-", with: "_")
        switch kind {
        case .helmet, .driverPhoto:
            let aliases = [
                "verstappen": "max_verstappen", "lindblad": "arvid_lindblad",
                "magnussen": "kevin_magnussen", "camara": "rafael_camara", "hirakawa": "ryo_hirakawa",
                "checo_perez": "perez", "kimi_antonelli": "antonelli", "andrea_kimi_antonelli": "antonelli"
            ]
            return aliases[slug] ?? id
        case .teamLogo, .carSide:
            let aliases = [
                "racing_bulls": "rb", "visa_cash_app_rb": "rb", "rb_f1_team": "rb",
                "red_bull_racing": "red_bull", "oracle_red_bull_racing": "red_bull",
                "haas_f1_team": "haas", "kick_sauber": "sauber", "stake_f1_team_kick_sauber": "sauber"
            ]
            return aliases[slug] ?? slug
        }
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
    public static func driverAvatarName(driverID: String? = nil, name: String, season: Int) -> String {
        helmetName(driverID: driverID, name: name, season: season)
    }

    public static func helmetName(driverID: String? = nil, name: String, season: Int) -> String {
        let surname = String(name.split(whereSeparator: \.isWhitespace).last ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let id = driverID ?? surname
        return self.name(kind: .helmet, id: id, season: season)
    }
}
