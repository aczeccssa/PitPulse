import Foundation
import SharedData

extension MobileModel {
    func startLive() {
        guard let serverURL else { return }
        guard !liveStarted || liveConnectionContext != dataContext else { return }
        liveConnectionContext = dataContext
        liveStarted = true
        liveConnecting = true
        #if DEBUG
        let liveURL = ProcessInfo.processInfo.environment["PITPULSE_LIVE_SERVER_URL"].flatMap(URL.init(string:)) ?? serverURL
        #else
        let liveURL = serverURL
        #endif
        for (series, store) in liveStores { store.start(serverURL: liveURL, token: currentToken, series: series) }
    }
    func stopLive() {
        liveStarted = false
        liveConnectionContext = nil
        liveConnecting = false
        for store in liveStores.values { store.stop() }
        liveSnapshots = [:]
        liveHistory = [:]
        historiesBySeries = [:]
        liveSnapshot = .disconnected()
        activity.end()
        widgetPublisher.clearLive()
    }
    func autoStartLiveOnce() { startLive() }
    func toggleLive() { if liveStarted { stopLive() } else { startLive() } }
    func selectLiveSeries(_ next: LiveSeries) {
        guard availableLiveSeries.contains(next), let snapshot = liveSnapshots[next] else { return }
        islandBattleNumbers = []
        series = next
        liveSnapshot = snapshot
        liveHistory = historiesBySeries[next] ?? [:]
        liveNotice = nil
        updateActivity()
    }
    func handle(_ snapshot: LiveSnapshot, from incomingSeries: LiveSeries) {
        if incomingSeries == series, liveSnapshot.sessionId != snapshot.sessionId { islandBattleNumbers = [] }
        let previousAvailable = Set(availableLiveSeries)
        let currentWasAvailable = previousAvailable.contains(series)
        liveSnapshots[incomingSeries] = snapshot
        var histories = historiesBySeries[incomingSeries] ?? [:]
        for driver in snapshot.drivers {
            guard let telemetry = driver.telemetry else { continue }
            var samples = histories[driver.number] ?? []
            guard samples.last?.utc != telemetry.utc else { continue }
            if let previous = samples.last, let previousDate = RFC3339.parse(previous.utc), let date = RFC3339.parse(telemetry.utc), date < previousDate { samples = [] }
            samples.append(telemetry)
            if samples.count > 90 { samples.removeFirst(samples.count - 90) }
            histories[driver.number] = samples
        }
        historiesBySeries[incomingSeries] = histories
        let available = availableLiveSeries
        if available.count < 2 { liveNotice = nil }
        if currentWasAvailable, !previousAvailable.contains(incomingSeries), available.contains(incomingSeries), incomingSeries != series {
            liveNotice = "\(incomingSeries.shortTitle) · \(snapshot.meetingName ?? "另一场比赛")" + (snapshot.sourceMode == .replay ? " 回放可观看" : " 也开始了")
        }
        if let selected = LiveSessionAvailability.selected(current: series, snapshots: liveSnapshots) { series = selected }
        if let selected = liveSnapshots[series] {
            liveSnapshot = selected
            liveHistory = historiesBySeries[series] ?? [:]
            liveConnecting = selected.statusReason == "connecting"
        }
        updateActivity()
        publishLiveWidget(snapshot)
    }
    func updateActivity() {
        activity.update(snapshot: liveSnapshot, mode: islandMode, favorite: favoriteLiveDriver, favoriteName: favoriteStanding?.driverName, selectedNumbers: islandBattleNumbers)
    }
    func endLiveActivity() {
        activity.end()
    }
}
