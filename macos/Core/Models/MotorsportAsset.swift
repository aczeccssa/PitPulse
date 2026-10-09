import AppKit

enum MotorsportAsset {
    enum Kind: Equatable { case helmet, teamLogo }

    static func name(kind: Kind, id: String, season: Int) -> String {
        let prefix = kind == .helmet ? "helmet" : "team-logo"
        return "\(prefix)-\(id)-\(season)"
    }

    static func image(kind: Kind, id: String, season: Int) -> NSImage? {
        NSImage(named: name(kind: kind, id: id, season: season))
    }

    static func abbreviation(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        return String((parts.last ?? name.prefix(3)).prefix(3)).uppercased()
    }
}
