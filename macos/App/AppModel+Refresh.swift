import AppKit
import Foundation
import SharedData

extension AppModel {
    func refreshPageData(target: ManualRefreshTarget? = nil) async {
        if target == .calendar {
            await refreshCalendar()
            return
        }
        if selectedResultSessionID == nil {
            selectedResultSessionID = availableResultSessions.first?.session.id
        }
        if target == nil || target == .results { await refreshResults() }
        if target == nil || target == .standings { await refreshStandings() }
    }

    func refreshCurrentPage(target: ManualRefreshTarget) {
        guard !isManualRefreshActive else { return }
        guard let server = configuredServer else {
            errorMessage = APIClientError.invalidServerAddress(serverAddress).localizedDescription
            return
        }
        if target == .results, selectedResultSessionID == nil {
            selectedResultSessionID = availableResultSessions.first?.session.id
        }
        guard target != .results || selectedResultSessionID != nil else {
            resultError = "当前赛季没有可刷新的 Session。"
            return
        }

        let season = selectedSeason
        let sessionID = target == .results ? selectedResultSessionID : nil
        let requestID = UUID()
        manualRefreshID = requestID
        isManualRefreshActive = true
        isRefreshing = true
        manualRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.manualRefreshID == requestID {
                    self.manualRefreshID = nil
                    self.manualRefreshTask = nil
                    self.isManualRefreshActive = false
                    self.isRefreshing = false
                }
            }
            await self.refreshPageData(target: target)
            guard server == self.configuredServer, season == self.selectedSeason,
                  target != .results || sessionID == self.selectedResultSessionID,
                  self.networkAvailable, !Task.isCancelled else { return }
            do {
                let token = try self.credentials.token(for: server.url)
                let client = APIClient(baseURL: server.url, session: self.session)
                let event = try await client.refresh(target: target, season: season, sessionId: sessionID, token: token)
                guard server == self.configuredServer, season == self.selectedSeason,
                      target != .results || sessionID == self.selectedResultSessionID else { return }
                if event.status == .completed || event.status == .partial {
                    await self.refreshPageData(target: target)
                } else {
                    self.setRefreshError(event, target: target)
                }
            } catch {
                guard server == self.configuredServer, season == self.selectedSeason,
                      target != .results || sessionID == self.selectedResultSessionID else { return }
                self.setRefreshError(error, target: target)
            }
        }
    }

    func menuSectionDidChange(target: ManualRefreshTarget) {
        Task { await refreshPageData(target: target) }
    }
    func handleDataRefresh(_ event: DataRefreshEvent) async {
        guard !isManualRefreshActive else { return }
        guard event.season == selectedSeason,
              event.status != .inProgress else { return }
        if event.target == .results, event.sessionId != selectedResultSessionID { return }
        switch event.status {
        case .completed, .partial:
            await refreshPageData(target: event.target)
        case .failed, .rateLimited:
            setRefreshError(event, target: event.target)
        case .inProgress:
            break
        }
    }

    func setRefreshError(_ event: DataRefreshEvent, target: ManualRefreshTarget) {
        let message = event.status == .rateLimited
            ? "上游限流，稍后再试。\(event.retryAfter.map { "下次尝试：\($0)" } ?? "")"
            : "上游刷新失败，保留现有缓存。"
        switch target {
        case .calendar: errorMessage = message
        case .results: resultError = message
        case .standings: standingsError = message
        }
    }

    func setRefreshError(_ error: Error, target: ManualRefreshTarget) {
        switch target {
        case .calendar: errorMessage = error.localizedDescription
        case .results: resultError = error.localizedDescription
        case .standings: standingsError = error.localizedDescription
        }
    }

    func refresh(force: Bool = false) {
        if !force,
           let lastSuccessfulAttemptAt,
           Date().timeIntervalSince(lastSuccessfulAttemptAt) < Self.refreshInterval {
            return
        }
        guard let server = configuredServer else {
            connectionStatus = .failed
            errorMessage = APIClientError.invalidServerAddress(serverAddress).localizedDescription
            return
        }

        let season = selectedSeason
        Task {
            await refreshCalendar(server: server, season: season)
        }
    }
    func refreshNow() async {
        await refreshCalendar()
    }
}
