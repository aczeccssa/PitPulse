import AppKit
import PitPulseComponents
import PitPulseShared

enum MotorsportAsset {
    enum Kind: Equatable { case helmet, driverPhoto, teamLogo, carSide }

    static func name(kind: Kind, id: String, season: Int) -> String {
        let sharedKind: MotorsportAssetName.Kind = switch kind {
        case .helmet: .helmet
        case .driverPhoto: .driverPhoto
        case .teamLogo: .teamLogo
        case .carSide: .carSide
        }
        return MotorsportAssetName.name(kind: sharedKind, id: id, season: season)
    }

    static func image(kind: Kind, id: String, season: Int) -> NSImage? {
        MotorsportImages.nsImage(named: name(kind: kind, id: id, season: season))
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
        MotorsportImages.nsImage(named: MotorsportAssetName.seriesLogoName(isWec: isWec))
    }

    static func abbreviation(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        return String((parts.last ?? name.prefix(3)).prefix(3)).uppercased()
    }
}
