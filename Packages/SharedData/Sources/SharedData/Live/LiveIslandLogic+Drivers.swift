import Foundation

extension LiveIslandLogic {
    public static func matchedDriver(
        favoriteId: String?,
        favorites: [FavoriteDriver],
        drivers: [LiveDriver]
    ) -> LiveDriver? {
        guard let favoriteId,
              let favorite = favorites.first(where: { $0.id == favoriteId })
        else {
            return nil
        }
        let name = normalizedDriverName(favorite.name)
        guard !name.isEmpty else { return nil }
        let matches = drivers.filter { normalizedDriverName($0.name ?? "") == name }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Follow state belongs to the driver, so a favourite car number driven by
    /// somebody else is not shown as followed.
    public static func isFavoriteDriver(_ driver: LiveDriver, favoriteId: String?, favorites: [FavoriteDriver]) -> Bool {
        guard favoriteId != nil else { return false }
        return matchedDriver(favoriteId: favoriteId, favorites: favorites, drivers: [driver]) != nil
    }

    public static func rosterID(for driver: LiveDriver, favorites: [FavoriteDriver]) -> String? {
        let name = normalizedDriverName(driver.name ?? "")
        guard !name.isEmpty else { return nil }
        let matches = favorites.filter { normalizedDriverName($0.name) == name }
        return matches.count == 1 ? matches[0].id : nil
    }

    public static func followableDriverID(for driver: LiveDriver, favorites: [FavoriteDriver], drivers: [LiveDriver]) -> String? {
        guard let id = rosterID(for: driver, favorites: favorites),
              matchedDriver(favoriteId: id, favorites: favorites, drivers: drivers)?.number == driver.number else { return nil }
        return id
    }

    /// WEC drivers are absent from the F1 roster, so follow them by car number.
    public static func followableID(for driver: LiveDriver, favorites: [FavoriteDriver], drivers: [LiveDriver], isWec: Bool) -> String? {
        isWec ? "wec:\(driver.number)" : followableDriverID(for: driver, favorites: favorites, drivers: drivers)
    }

    public static func favorites(for series: LiveSeries, in favorites: [FavoriteDriver]) -> [FavoriteDriver] {
        favorites.filter { series == .wec ? $0.id.hasPrefix("wec:") : !$0.id.hasPrefix("wec:") }
    }

    private static func normalizedDriverName(_ name: String) -> String {
        let normalized = normalizedName(name)
        // Live uses Kimi Antonelli; the roster uses his full name Andrea Kimi Antonelli.
        return normalized == "kimi antonelli" ? "andrea kimi antonelli" : normalized
    }
}
