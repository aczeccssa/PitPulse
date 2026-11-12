import AppKit
import Foundation
import SharedData

extension AppModel {
    func markOffline() {
        connectionStatus = .offline
        if meetings.isEmpty { lastSuccessfulLoadAt = nil }
    }

    func refreshCalendar(server: ServerAddress? = nil, season: Int? = nil) async {
        let targetServer = server ?? configuredServer
        let targetSeason = season ?? selectedSeason
        guard networkAvailable else { markOffline(); return }
        if let activeRefreshTask {
            await activeRefreshTask.value
            return
        }
        let requestID = UUID()
        activeRefreshID = requestID
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(server: targetServer, season: targetSeason)
        }
        activeRefreshTask = task
        await task.value
        if activeRefreshID == requestID {
            activeRefreshTask = nil
            activeRefreshID = nil
        }
    }

    func invalidateConnection() {
        widgetPublisher?.clear()
        generation += 1
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        activeRefreshID = nil
        manualRefreshTask?.cancel()
        manualRefreshTask = nil
        manualRefreshID = nil
        isManualRefreshActive = false
        retryTask?.cancel()
        resultGeneration += 1
        standingsGeneration += 1
        lastSuccessfulLoadAt = nil
        lastSuccessfulAttemptAt = nil
        isRefreshing = false
        isTokenStored = false
        connectionStatus = .idle
        selectedResultSessionID = nil
        sessionResults = []
        resultMeta = nil
        resultError = nil
        widgetStandings = []
        widgetStandingsSavedAt = .distantPast
        widgetRecentRaces = []
        widgetHighlightsKey = nil
        widgetHighlightsLoadedAt = nil
        driverStandings = []
        constructorStandings = []
        standingsMeta = nil
        standingsError = nil
    }
    func performRefresh(server: ServerAddress?, season: Int) async {
        guard let server, server == configuredServer, season == selectedSeason else { return }
        generation += 1
        let requestGeneration = generation
        isRefreshing = true
        if meetings.isEmpty {
            connectionStatus = .loading
        }

        do {
            let token = try credentials.token(for: server.url)
            let client = APIClient(baseURL: server.url, session: session)
            async let calendarEnvelope = client.calendar(season: season, token: token)
            async let nextEnvelope = client.nextMeeting(season: season, token: token)
            let (calendarResponse, nextResponse) = try await (calendarEnvelope, nextEnvelope)

            guard requestGeneration == generation else { return }
            meetings = calendarResponse.data
            meta = calendarResponse.meta
            nextMeetingOverride = validServerNextMeeting(nextResponse.data)
            // Do not stamp server-stale data as freshly fetched.
            widgetPublisher?.publishCalendar(meetings: nextMeetingOverride.map { next in
                meetings.filter { $0.id != next.id } + [next]
            } ?? meetings,
                savedAt: calendarResponse.meta.stale ? .distantPast : (calendarResponse.meta.fetchedAt ?? .distantPast))
            lastSuccessfulLoadAt = Date()
            lastSuccessfulAttemptAt = Date()
            errorMessage = nil
            connectionStatus = networkAvailable ? (calendarResponse.meta.stale ? .stale : .connected) : .offline
            isTokenStored = token != nil
            retryAttempt = 0
            retryTask?.cancel()
            do {
                try await cache.save(server: server.url, season: season, envelope: calendarResponse)
            } catch {
                if requestGeneration == generation {
                    settingsMessage = "数据已读取，但缓存写入失败：\(error.localizedDescription)"
                }
            }
            if remindersEnabled { await syncReminders(calendarResponse.data, server: server, season: season) }
            Task {
                await refreshPageData()
                await refreshWidgetHighlights()
            }
        } catch {
            guard requestGeneration == generation else { return }
            let unauthorized = error as? APIClientError == .unauthorized
            errorMessage = error.localizedDescription
            if !networkAvailable {
                connectionStatus = .offline
            } else if unauthorized {
                connectionStatus = .requiresToken
            } else if meetings.isEmpty {
                connectionStatus = .failed
            } else {
                connectionStatus = .stale
            }
            if unauthorized { widgetPublisher?.clear() }
            if !unauthorized { Task { await refreshPageData() } }
            scheduleRetry(for: error)
        }
        if requestGeneration == generation && !isManualRefreshActive { isRefreshing = false }
    }

    func scheduleRetry(for error: Error) {
        guard networkAvailable, !(error is CancellationError) else { return }
        let delay: TimeInterval
        if error as? APIClientError == .unauthorized { return }
        if case let APIClientError.rateLimited(retryAfter)? = error as? APIClientError, let retryAfter {
            delay = max(0, retryAfter.timeIntervalSinceNow)
        } else {
            delay = retryDelays[min(retryAttempt, retryDelays.count - 1)]
            retryAttempt += 1
        }
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.networkAvailable else { return }
            await self.refreshCalendar()
        }
    }
}
