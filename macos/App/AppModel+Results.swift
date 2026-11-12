import AppKit
import Foundation
import SharedData

extension AppModel {
    func selectResultSession(_ sessionID: String) {
        guard selectedResultSessionID != sessionID else { return }
        resultGeneration += 1
        selectedResultSessionID = sessionID
        sessionResults = []
        resultMeta = nil
        resultError = nil
        Task { await refreshResults() }
    }

    func selectStandings(isConstructor: Bool) {
        guard showingConstructorStandings != isConstructor else { return }
        standingsGeneration += 1
        showingConstructorStandings = isConstructor
        standingsError = nil
        Task { await refreshStandings() }
    }
    func refreshResults() async {
        guard let sessionID = selectedResultSessionID,
              let server = configuredServer else { return }
        resultGeneration += 1
        let requestGeneration = resultGeneration
        let season = selectedSeason
        let client = APIClient(baseURL: server.url, session: session)
        if sessionResults.isEmpty {
            await loadResultsCache(sessionID: sessionID, requestGeneration: requestGeneration)
        }
        guard networkAvailable else { resultError = "离线，当前显示缓存数据。"; return }
        do {
            let token = try credentials.token(for: server.url)
            let response = try await client.sessionResults(sessionId: sessionID, token: token)
            guard requestGeneration == resultGeneration, server == configuredServer,
                  season == selectedSeason, sessionID == selectedResultSessionID else { return }
            sessionResults = response.data
            resultMeta = response.meta
            resultError = nil
            try? await cache.save(server: server.url, season: season, key: "results-\(sessionID)", envelope: response)
        } catch {
            guard requestGeneration == resultGeneration, server == configuredServer,
                  season == selectedSeason, sessionID == selectedResultSessionID else { return }
            if sessionResults.isEmpty,
               let cached = try? await cache.load(server: server.url, season: season, key: "results-\(sessionID)", as: [SessionResult].self) {
                sessionResults = cached.data
                resultMeta = cached.meta
            }
            resultError = error.localizedDescription
        }
    }

    func refreshStandings() async {
        guard let server = configuredServer else { return }
        standingsGeneration += 1
        let requestGeneration = standingsGeneration
        let season = selectedSeason
        let client = APIClient(baseURL: server.url, session: session)
        if showingConstructorStandings ? constructorStandings.isEmpty : driverStandings.isEmpty {
            await loadStandingsCache(server: server, season: season, isConstructor: showingConstructorStandings, requestGeneration: requestGeneration)
        }
        guard networkAvailable else { standingsError = "离线，当前显示缓存数据。"; return }
        do {
            let token = try credentials.token(for: server.url)
            if showingConstructorStandings {
                let response = try await client.constructorStandings(season: season, token: token)
                guard requestGeneration == standingsGeneration, server == configuredServer, season == selectedSeason,
                      showingConstructorStandings else { return }
                constructorStandings = response.data
                standingsMeta = response.meta
                try? await cache.save(server: server.url, season: season, key: "standings-constructors", envelope: response)
            } else {
                let response = try await client.driverStandings(season: season, token: token)
                guard requestGeneration == standingsGeneration, server == configuredServer, season == selectedSeason,
                      !showingConstructorStandings else { return }
                driverStandings = response.data
                standingsMeta = response.meta
                publishWidgetStandings(response.data, meta: response.meta)
                try? await cache.save(server: server.url, season: season, key: "standings-drivers", envelope: response)
            }
            standingsError = nil
        } catch {
            guard requestGeneration == standingsGeneration, server == configuredServer, season == selectedSeason else { return }
            let key = showingConstructorStandings ? "standings-constructors" : "standings-drivers"
            if showingConstructorStandings, constructorStandings.isEmpty,
               let cached = try? await cache.load(server: server.url, season: season, key: key, as: [ConstructorStanding].self) {
                constructorStandings = cached.data
                standingsMeta = cached.meta
            } else if !showingConstructorStandings, driverStandings.isEmpty,
                      let cached = try? await cache.load(server: server.url, season: season, key: key, as: [DriverStanding].self) {
                driverStandings = cached.data
                standingsMeta = cached.meta
            }
            standingsError = error.localizedDescription
        }
    }
    func ensureDriverStandingsLoaded() {
        guard driverStandings.isEmpty, let server = configuredServer else { return }
        let season = selectedSeason
        Task { [weak self] in
            guard let self else { return }
            if let cached = try? await self.cache.load(server: server.url, season: season, key: "standings-drivers", as: [DriverStanding].self),
               self.selectedSeason == season, self.driverStandings.isEmpty {
                self.driverStandings = cached.data
                self.standingsMeta = cached.meta
            }
            guard self.driverStandings.isEmpty, self.networkAvailable else { return }
            do {
                let token = try self.credentials.token(for: server.url)
                let response = try await APIClient(baseURL: server.url, session: self.session)
                    .driverStandings(season: season, token: token)
                guard self.selectedSeason == season, self.configuredServer == server else { return }
                self.driverStandings = response.data
                self.standingsMeta = response.meta
                try? await self.cache.save(server: server.url, season: season, key: "standings-drivers", envelope: response)
            } catch {
                guard self.selectedSeason == season, self.configuredServer == server else { return }
                self.standingsError = error.localizedDescription
            }
        }
    }
    func loadResultsCache(sessionID: String, requestGeneration: Int? = nil) async {
        guard let server = configuredServer else { return }
        let season = selectedSeason
        guard let cached = try? await cache.load(server: server.url, season: season, key: "results-\(sessionID)", as: [SessionResult].self),
              server == configuredServer, season == selectedSeason,
              selectedResultSessionID == sessionID,
              requestGeneration == nil || requestGeneration == resultGeneration,
              sessionResults.isEmpty else { return }
        sessionResults = cached.data
        resultMeta = cached.meta
    }

    func loadStandingsCache(server: ServerAddress, season: Int, isConstructor: Bool, requestGeneration: Int) async {
        if isConstructor,
           let cached = try? await cache.load(server: server.url, season: season, key: "standings-constructors", as: [ConstructorStanding].self),
           server == configuredServer, season == selectedSeason, requestGeneration == standingsGeneration,
           showingConstructorStandings, constructorStandings.isEmpty {
            constructorStandings = cached.data
            standingsMeta = cached.meta
        } else if !isConstructor,
                  let cached = try? await cache.load(server: server.url, season: season, key: "standings-drivers", as: [DriverStanding].self),
                  server == configuredServer, season == selectedSeason, requestGeneration == standingsGeneration,
                  !showingConstructorStandings, driverStandings.isEmpty {
            driverStandings = cached.data
            standingsMeta = cached.meta
        }
    }
}
