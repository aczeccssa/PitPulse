import AppKit
import Foundation
import SharedData
import SharedComponents

extension AppModel {
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        refreshMedia()
        await loadCachedIfAvailable()
        await refreshTokenStatus()
        if networkAvailable {
            startLiveStream()
            await refreshCalendar()
        }
        else { markOffline(); await refreshPageData() }
    }

    func popupDidAppear() {
        refreshMedia()
        startPopupRefresh()
        if !didBootstrap {
            Task { await bootstrap() }
            return
        }
        Task {
            await refreshCalendar()
            await refreshPageData()
        }
    }

    func popupDidDisappear() {
        popupRefreshTask?.cancel()
        popupRefreshTask = nil
    }
    func networkPathDidChange(isAvailable: Bool) {
        guard networkAvailable != isAvailable else { return }
        networkAvailable = isAvailable
        if isAvailable {
            retryAttempt = 0
            retryTask?.cancel()
            if didBootstrap { startLiveStream() }
            refresh(force: true)
        } else {
            liveStore.stop(reason: "offline")
            markOffline()
            retryTask?.cancel()
        }
    }

    func prepareForSleep() {
        generation += 1
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        activeRefreshID = nil
        manualRefreshTask?.cancel()
        manualRefreshTask = nil
        manualRefreshID = nil
        isManualRefreshActive = false
        isRefreshing = false
        retryTask?.cancel()
        popupRefreshTask?.cancel()
        popupRefreshTask = nil
        liveStore.stop(reason: "sleep")
        markOffline()
    }

    func resumeAfterWake() async {
        markOffline()
        if networkAvailable {
            await refreshTokenStatus()
            if didBootstrap { startLiveStream() }
            await refreshCalendar()
        }
        else { await refreshPageData() }
    }
    func mapData(path: String) async throws -> Data {
        guard let server = configuredServer else { throw APIClientError.transport("请先配置服务器") }
        let address = serverAddress
        let result = try await APIClient(baseURL: server.url, session: session).mapData(path: path, token: credentials.token(for: server.url))
        guard address == serverAddress else { throw CancellationError() }
        return result
    }

    private func refreshMedia() {
        let token = serverURL.flatMap { try? credentials.token(for: $0) }
        MediaCache.shared.refresh(from: serverURL, token: token, online: networkAvailable)
    }

    func startLiveStream() {
        refreshMedia()
        guard didBootstrap, networkAvailable, let server = configuredServer else { return }
        do {
            liveStore.start(
                serverURL: server.url,
                token: try credentials.token(for: server.url),
                series: liveSeries
            )
        } catch {
            liveStore.stop(reason: "credentials_unavailable")
        }
    }
    func startPopupRefresh() {
        guard popupRefreshTask == nil else { return }
        let interval = popupRefreshInterval
        popupRefreshTask = Task { @MainActor [weak self, interval] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await self.refreshNow()
            }
        }
    }
}
