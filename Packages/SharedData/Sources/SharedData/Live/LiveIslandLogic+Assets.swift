import Foundation

extension LiveIslandLogic {
    /// Constructor id for a bundled team-logo asset.
    public static func teamAssetID(for driver: LiveDriver, isWec: Bool) -> String? {
        isWec ? wecTeamAssetID(for: driver) : f1TeamAssetID(for: driver)
    }

    /// WEC bundles one side view per car number; F1 publishes one per team.
    public static func carSideAssetID(for driver: LiveDriver, isWec: Bool) -> String? {
        isWec ? driver.number : f1TeamAssetID(for: driver)
    }

    private static func f1TeamAssetID(for driver: LiveDriver) -> String? {
        let known = [
            "red bull": "red_bull",
            "mercedes": "mercedes",
            "mclaren": "mclaren",
            "ferrari": "ferrari",
            "williams": "williams",
            "racing bulls": "rb",
            "aston martin": "aston_martin",
            "alpine": "alpine",
            "haas": "haas",
            "audi": "audi",
            "cadillac": "cadillac"
        ]
        for source in [driver.manufacturer, driver.team].compactMap({ $0?.lowercased() }) {
            if let id = known.first(where: { source.contains($0.key) })?.value {
                return id
            }
        }
        return nil
    }

    /// Marque logos bundled from the official WEC grid.
    private static let wecBrands: [(key: String, id: String)] = [
        ("alpine", "wec_alpine"),
        ("aston martin", "wec_aston_martin"),
        ("bmw", "wec_bmw"),
        ("cadillac", "wec_cadillac"),
        ("corvette", "wec_corvette"),
        ("ferrari", "wec_ferrari"),
        ("ford", "wec_ford"),
        ("genesis", "wec_genesis"),
        ("lexus", "wec_lexus"),
        ("mclaren", "wec_mclaren"),
        ("mercedes", "wec_mercedes"),
        ("peugeot", "wec_peugeot"),
        ("porsche", "wec_porsche"),
        ("toyota", "wec_toyota")
    ]

    /// Manufacturer logo for the WEC timing list, which shows the marque
    /// rather than the current driver portrait.
    public static func wecManufacturerAssetID(for driver: LiveDriver) -> String? {
        let source = (driver.manufacturer ?? "").lowercased()
        guard !source.isEmpty else { return nil }
        return wecBrands.first(where: { source.contains($0.key) })?.id
    }

    /// WEC teams publish their own logos for customer entries; manufacturer
    /// teams fall back to the marque logo used by the official grid.
    private static func wecTeamAssetID(for driver: LiveDriver) -> String? {
        let teams = [
            "garage 59": "wec_garage_59",
            "heart of racing team": "wec_heart_of_racing",
            "team wrt": "wec_team_wrt",
            "tf sport": "wec_tf_sport",
            "iron lynx": "wec_iron_lynx",
            "proton competition": "wec_proton_competition",
            "akkodis asp team": "wec_akkodis_asp",
            "manthey dk engineering": "wec_manthey_dk",
            "the bend manthey": "wec_the_bend_manthey"
        ]
        let team = normalizedName(driver.team ?? "")
        if let id = teams[team] { return id }
        for source in [driver.manufacturer, driver.team].compactMap({ $0?.lowercased() }) {
            if let id = wecBrands.first(where: { source.contains($0.key) })?.id { return id }
        }
        return nil
    }

    /// File-name id for the official WEC driver portrait bundled for a season.
    public static func driverAssetID(for driver: LiveDriver) -> String? {
        guard let name = driver.name, !name.isEmpty else { return nil }
        return assetSlug(name)
    }

    public static func assetSlug(_ value: String) -> String {
        let replacements = ["ø": "o", "Ø": "O", "æ": "ae", "Æ": "AE", "œ": "oe", "Œ": "OE", "ß": "ss", "ł": "l", "Ł": "L", "đ": "d", "Đ": "D", "ð": "d", "Ð": "D", "þ": "th", "Þ": "TH"]
        var text = value
        for (from, to) in replacements { text = text.replacingOccurrences(of: from, with: to) }
        return text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
            .lowercased()
    }

    /// Sector values arrive as "30.452" or "1:34.951"; WEC has no per-segment
    /// data, so this feeds the class-relative pace color of its sector bars.
    public static func sectorSeconds(_ value: String) -> Double? {
        let text = value.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: ":")
        if parts.count == 2 {
            guard let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        }
        return Double(text)
    }
}
