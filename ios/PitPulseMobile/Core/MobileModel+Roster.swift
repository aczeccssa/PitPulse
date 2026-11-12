import Foundation
import SharedData

extension MobileModel {
    var sortedDrivers: [LiveDriver] {
        liveSnapshot.drivers.sorted {
            let left = $0.position ?? $0.classPosition ?? Int.max
            let right = $1.position ?? $1.classPosition ?? Int.max
            return left == right ? $0.number < $1.number : left < right
        }
    }
    var availableLiveSeries: [LiveSeries] {
        LiveSeries.allCases.filter { liveSnapshots[$0].map { LiveSessionAvailability.isAvailable($0) } ?? false }
    }
    var hasActiveLive: Bool { !availableLiveSeries.isEmpty }
    var favoriteStanding: DriverStanding? { driverRoster.first { $0.id == favoriteDriverID } }
    var favoriteLiveDriver: LiveDriver? {
        guard let favoriteDriverID else { return nil }
        return liveSnapshot.drivers.first { driverID(for: $0) == favoriteDriverID }
    }
    func driverID(for driver: LiveDriver) -> String? {
        guard !liveSnapshot.isWec else { return nil }
        let roster = driverRoster.map { FavoriteDriver(id: $0.id, name: $0.driverName) }
        if let exact = LiveIslandLogic.rosterID(for: driver, favorites: roster) { return exact }
        guard let surname = driver.name?.split(whereSeparator: \.isWhitespace).last else { return nil }
        let key = LiveIslandLogic.assetSlug(String(surname))
        let matches = driverRoster.filter { LiveIslandLogic.assetSlug(String($0.driverName.split(whereSeparator: \.isWhitespace).last ?? "")) == key }
        return matches.count == 1 ? matches[0].id : nil
    }
    func helmetAsset(for driver: LiveDriver) -> String {
        MotorsportAssetName.helmetName(driverID: driverID(for: driver), name: driver.name ?? "", season: season)
    }
    func loadF1Roster(force: Bool = false) async {
        guard force || driverRoster.isEmpty, let serverURL else { return }
        let context = dataContext
        rosterLoadError = nil
        do {
            let response = try await APIClient(baseURL: serverURL).driverStandings(season: season, token: currentToken)
            guard context == dataContext, !Task.isCancelled else { return }
            driverRoster = response.data
            rosterLoadError = driverRoster.isEmpty ? "当前服务器暂无 F1 车手数据，请检查服务地址。" : nil
            let savedAt = response.meta.stale ? .distantPast : (response.meta.fetchedAt ?? .now)
            widgetPublisher.publishStandings(response.data, season: season, savedAt: savedAt)
            rosterSavedAt = savedAt
            publishFavoriteWidget()
            updateActivity()
        } catch { if !Task.isCancelled { rosterLoadError = Self.message(for: error) } }
    }
}
