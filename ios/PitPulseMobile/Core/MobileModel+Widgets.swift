import Foundation
import SharedData

extension MobileModel {
    func publishWidget(savedAt: Date = .now) {
        widgetPublisher.publishCalendar(meetings: meetings, savedAt: savedAt)
    }
    func publishFavoriteWidget() {
        guard let favoriteDriverID else {
            widgetPublisher.publishFavoriteDriver([], favoriteID: nil, season: season, savedAt: rosterSavedAt)
            return
        }
        guard !driverRoster.isEmpty else { return }
        let savedAt = recentRaceSources.isEmpty ? rosterSavedAt : min(rosterSavedAt, recentRaceSavedAt)
        widgetPublisher.publishFavoriteDriver(driverRoster, favoriteID: favoriteDriverID,
            season: season, savedAt: savedAt, recentRaces: recentRaceSources)
    }
    func publishLiveWidget(_ snapshot: LiveSnapshot) {
        widgetPublisher.publishLive(snapshot)
    }
}
