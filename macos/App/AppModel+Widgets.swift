import AppKit
import Foundation
import SharedData

extension AppModel {
    func publishWidgetStandings(_ standings: [DriverStanding], meta: ResponseMeta) {
        widgetStandings = standings
        widgetStandingsSavedAt = meta.stale ? .distantPast : (meta.fetchedAt ?? .distantPast)
        widgetPublisher?.publishStandings(standings, season: selectedSeason, savedAt: widgetStandingsSavedAt)
        publishFavoriteWidget()
    }

    func publishFavoriteWidget() {
        let savedAt = ([widgetStandingsSavedAt] + widgetRecentRaces.map(\.savedAt)).min() ?? .distantPast
        widgetPublisher?.publishFavoriteDriver(widgetStandings, favoriteID: favoriteDriverId,
            season: selectedSeason, savedAt: savedAt, recentRaces: widgetRecentRaces)
    }

    func refreshWidgetHighlights() async {
        guard widgetPublisher != nil, networkAvailable, let server = configuredServer else { return }
        let season = selectedSeason
        let requestGeneration = generation
        let now = Date()
        let races = meetings.filter { $0.status != .cancelled && $0.status != .postponed }
            .flatMap { meeting in
                meeting.sessions.filter { session in
                    guard session.sessionType == .race, session.status != .cancelled,
                          session.status != .postponed, session.status != .live else { return false }
                    return session.status == .finished || (session.endTime ?? session.startTime.addingTimeInterval(3 * 3600)) < now
                }.map { (meeting: meeting, session: $0) }
            }.sorted { $0.session.startTime > $1.session.startTime }.prefix(3)
        let key = "\(requestGeneration)|\(season)|" + races.map { $0.session.id }.joined(separator: ",")
        if widgetHighlightsKey == key, let loadedAt = widgetHighlightsLoadedAt,
           now.timeIntervalSince(loadedAt) < 900 { return }
        let client = APIClient(baseURL: server.url, session: session)
        let token = try? credentials.token(for: server.url)
        do {
            let response = try await client.driverStandings(season: season, token: token)
            guard generation == requestGeneration, selectedSeason == season, configuredServer == server,
                  !Task.isCancelled else { return }
            publishWidgetStandings(response.data, meta: response.meta)
        } catch {
            // Retain the last dated snapshot if the standings request fails.
        }
        var sources: [FavoriteRaceSource] = []
        for race in races {
            do {
                let response = try await client.sessionResults(sessionId: race.session.id, token: token)
                guard generation == requestGeneration, selectedSeason == season, configuredServer == server,
                      !Task.isCancelled else { return }
                guard !response.data.isEmpty else { continue }
                sources.append(FavoriteRaceSource(meeting: race.meeting, session: race.session,
                    results: response.data, savedAt: response.meta.stale ? .distantPast : (response.meta.fetchedAt ?? .distantPast)))
            } catch { continue }
        }
        guard generation == requestGeneration, selectedSeason == season, configuredServer == server,
              !Task.isCancelled else { return }
        if let newest = races.first, let source = sources.first(where: { $0.session.id == newest.session.id }) {
            widgetRecentRaces = sources
            widgetPublisher?.publishLastRace(meeting: source.meeting, session: source.session,
                results: source.results, savedAt: source.savedAt)
            publishFavoriteWidget()
        } else if !races.isEmpty {
            return
        }
        widgetHighlightsKey = key
        widgetHighlightsLoadedAt = now
    }
}
