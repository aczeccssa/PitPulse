import AppKit

enum MotorsportAsset {
    enum Kind: Equatable { case helmet, driverPhoto, teamLogo, carSide }

    static func name(kind: Kind, id: String, season: Int) -> String {
        let prefix = switch kind {
        case .helmet: "helmet"
        case .driverPhoto: "driver-photo"
        case .teamLogo: "team-logo"
        case .carSide: "car-side"
        }
        let id = kind == .helmet ? ["verstappen": "max_verstappen", "lindblad": "arvid_lindblad"][id] ?? id : id
        return "\(prefix)-\(id)-\(season)"
    }

    static func image(kind: Kind, id: String, season: Int) -> NSImage? {
        NSImage(named: name(kind: kind, id: id, season: season))
    }

    static func f1DriverImage(id: String, season: Int) -> NSImage? {
        image(kind: .helmet, id: id, season: season)
            ?? image(kind: .driverPhoto, id: id, season: season)
    }

    /// Popup pages always show the driver's helmet; a portrait is never used as
    /// a stand-in. Drivers without a helmet asset fall back to abbreviations.
    static func f1HelmetImage(id: String, season: Int) -> NSImage? {
        image(kind: .helmet, id: id, season: season)
    }

    /// Official series mark shown where the country flag used to be.
    static func seriesLogo(isWec: Bool) -> NSImage? {
        NSImage(named: isWec ? "series-wec" : "series-f1")
    }

    static func abbreviation(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        return String((parts.last ?? name.prefix(3)).prefix(3)).uppercased()
    }
}
