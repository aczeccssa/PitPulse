import Foundation
import SharedData
import BackgroundTasks
import UIKit

struct LiveCompletedLap {
    let number: Int
    let time: String
}

extension MobileModel {
    nonisolated static let activityRefreshIdentifier = "com.pitpulse.mobile.live-activity-refresh"

    var liveServerURL: URL? {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["PITPULSE_LIVE_SERVER_URL"], let url = URL(string: value) { return url }
        #endif
        return serverURL
    }

    func startLive() {
        guard let liveServerURL, !liveStarted || liveConnectionContext != dataContext else { return }
        connectLive(at: liveServerURL)
    }

    func refreshLive() {
        guard let liveServerURL else { settingsPresented = true; return }
        connectLive(at: liveServerURL)
    }

    private func connectLive(at liveURL: URL) {
        liveConnectionContext = dataContext
        liveStarted = true
        liveConnecting = true
        for (series, store) in liveStores { store.start(serverURL: liveURL, token: currentToken, series: series) }
    }
    func stopLive() {
        liveStarted = false
        liveConnectionContext = nil
        liveConnecting = false
        for store in liveStores.values { store.stop() }
        liveSnapshots = [:]
        liveEntries = [:]
        liveNotice = nil
        manuallySelectedLiveSeries = nil
        liveHistory = [:]
        historiesBySeries = [:]
        recentLiveLaps = [:]
        refreshLiveSelection()
        activity.end()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.activityRefreshIdentifier)
        widgetPublisher.clearLive()
    }
    func autoStartLiveOnce() { startLive() }
    func toggleLive() { if liveStarted { stopLive() } else { startLive() } }
    func selectLiveSeries(_ next: LiveSeries) {
        guard availableLiveSeries.contains(next) else { return }
        manuallySelectedLiveSeries = next
        if liveNotice?.series == next { liveNotice = nil }
        refreshLiveSelection()
        updateActivity()
    }

    func refreshLiveSelection() {
        let available = availableLiveSeries
        if let manual = manuallySelectedLiveSeries, !available.contains(manual) {
            manuallySelectedLiveSeries = nil
        }
        let preferred = manuallySelectedLiveSeries ?? preferredLiveSeries
        let next = available.contains(preferred) ? preferred : (available.first ?? preferred)
        let current = liveSnapshots[next] ?? .disconnected()
        let entry = liveEntries[next]
        var displayed = current
        displayed.series = next.rawValue
        if entry == nil, next == .f1, let planned = scheduledLiveSession, current.sessionId != nil {
            let matchesSchedule = current.meetingName == planned.meeting.name
                && [current.sessionType, current.sessionName].compactMap { $0 }.contains {
                    LiveIslandLogic.sessionTypeMatches($0, planned.session.sessionType)
                }
            if !matchesSchedule || LiveIslandLogic.isFinished(current.sessionStatus) {
                displayed = .disconnected(reason: "awaiting_timing")
                displayed.series = next.rawValue
            }
        }
        if let id = displayed.sessionId ?? entry?.sessionId {
            let key = "\(next.rawValue):\(id)"
            if let previous = displayedLiveSessionKey, previous != key { islandBattleNumbers = [] }
            displayedLiveSessionKey = key
        }
        series = next
        liveSnapshot = displayed
        liveHistory = displayed.sessionId == nil ? [:] : (historiesBySeries[next] ?? [:])
        liveConnecting = current.statusReason == "connecting" || current.statusReason == "reconnecting"
    }

    func handle(_ snapshot: LiveSnapshot, from incomingSeries: LiveSeries) {
        let previous = liveSnapshots[incomingSeries].flatMap { $0.sessionId == nil ? nil : $0 }
            ?? liveEntries[incomingSeries]
        let previousAvailable = Set(liveEntries.keys)
        let currentWasAvailable = previousAvailable.contains(series)
        if let id = snapshot.sessionId {
            if LiveIslandLogic.isActive(snapshot.sessionStatus) {
                liveEntries[incomingSeries] = snapshot
            } else if let prior = liveEntries[incomingSeries],
                      prior.sessionId != id || LiveIslandLogic.isFinished(snapshot.sessionStatus) {
                liveEntries[incomingSeries] = nil
            }
        }
        if snapshot.sessionId == nil {
            liveSnapshots[incomingSeries] = snapshot.retainingTiming(from: liveSnapshots[incomingSeries])
            refreshLiveSelection()
            return
        }
        if incomingSeries == .f1, snapshot.sourceMode == .live, LiveIslandLogic.isFinished(snapshot.sessionStatus) {
            lastFinishedF1 = snapshot
            updateScheduledLiveSession()
        }
        if let previous, let session = snapshot.sessionId {
            let rewound = previous.lapCount.flatMap { before in snapshot.lapCount.map { $0 < before } } ?? false
            if previous.sessionId != session || rewound {
                recentLiveLaps[incomingSeries] = nil
                historiesBySeries[incomingSeries] = nil
            }
        }
        liveSnapshots[incomingSeries] = snapshot
        recordCompletedLaps(snapshot.drivers, for: incomingSeries)
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
        if let notice = liveNotice, !available.contains(notice.series) { liveNotice = nil }
        if currentWasAvailable, !previousAvailable.contains(incomingSeries), available.contains(incomingSeries), incomingSeries != series {
            let suffix = snapshot.sourceMode == .replay ? "replay available" : "has started"
            liveNotice = LiveNotice(series: incomingSeries,
                                    text: "\(incomingSeries.shortTitle) · \(snapshot.meetingName ?? incomingSeries.title) \(suffix)")
        }
        refreshLiveSelection()
        if LiveIslandLogic.isFinished(snapshot.sessionStatus),
           activity.activeSeries == incomingSeries {
            activity.update(snapshot: snapshot, existingOnly: true)
        }
        updateActivity()
        publishLiveWidget(snapshot)
    }
    var liveMeetingName: String {
        liveEntries[series]?.meetingName ?? (series == .f1 ? scheduledLiveSession?.meeting.name : nil)
            ?? liveSnapshot.meetingName ?? "Waiting for timing"
    }

    var liveCountryCode: String? {
        liveEntries[series]?.countryCode ?? (series == .f1 ? scheduledLiveSession?.meeting.countryCode : nil)
            ?? liveSnapshot.countryCode
    }

    var liveSessionName: String {
        if series == .f1, liveEntries[.f1] == nil, let scheduledLiveSession {
            return scheduledLiveSession.session.sessionType.resultLabel
        }
        return (liveEntries[series]?.sessionName ?? liveSnapshot.sessionName).map(LiveIslandLogic.sessionLabel) ?? series.title
    }

    var liveScheduleForDisplay: NextSession? {
        guard series == .f1, let scheduledLiveSession else { return nil }
        guard let entry = liveEntries[.f1] else { return scheduledLiveSession }
        guard entry.sourceMode == .live, entry.meetingName == scheduledLiveSession.meeting.name,
              [entry.sessionType, entry.sessionName].compactMap({ $0 }).contains(where: {
                  LiveIslandLogic.sessionTypeMatches($0, scheduledLiveSession.session.sessionType)
              }) else { return nil }
        return scheduledLiveSession
    }

    func loadCurrentSeasonLiveCalendar() async {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: .now)
        guard season != currentYear, let serverURL else { return }
        let context = dataContext
        guard let response = try? await APIClient(baseURL: serverURL).calendar(season: currentYear, token: currentToken),
              !Task.isCancelled, dataContext == context else { return }
        currentSeasonLiveMeetings = response.data
        updateScheduledLiveSession()
    }

    func updateScheduledLiveSession(now: Date = .now) {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: now)
        let calendar = season == currentYear ? meetings : currentSeasonLiveMeetings
        let candidate = calendar.filter { $0.status == .scheduled }.flatMap { meeting in
            meeting.sessions.compactMap { session -> NextSession? in
                let fallbackEnd = session.startTime.addingTimeInterval(session.sessionType.liveEntryDuration)
                guard session.status == .live || session.status == .scheduled, session.startTime <= now,
                      session.status == .live || now < max(session.endTime ?? fallbackEnd, fallbackEnd)
                else { return nil }
                if let lastFinishedF1, let finishedAt = lastFinishedF1.updatedAt.flatMap(RFC3339.parse),
                   finishedAt >= session.startTime,
                   lastFinishedF1.meetingName == nil || lastFinishedF1.meetingName == meeting.name,
                   let label = lastFinishedF1.sessionType ?? lastFinishedF1.sessionName,
                   LiveIslandLogic.sessionTypeMatches(label, session.sessionType) { return nil }
                return NextSession(meeting: meeting, session: session)
            }
        }.max { $0.session.startTime < $1.session.startTime }
        if candidate != scheduledLiveSession {
            scheduledLiveSession = candidate
            refreshLiveSelection()
        }
        for (series, entry) in liveEntries where entry.sourceMode == .replay {
            let window: TimeInterval = series == .wec ? 26 * 3600 : 4 * 3600
            if let at = entry.updatedAt ?? entry.lastTransportAt,
               !LiveFreshness.isFresh(at, now: now, maximumAge: window) {
                liveEntries[series] = nil
                refreshLiveSelection()
            }
        }
    }

    private func recordCompletedLaps(_ drivers: [LiveDriver], for incomingSeries: LiveSeries) {
        for driver in drivers {
            guard let number = driver.lapCount, number > 0, let time = driver.lastLap,
                  let seconds = LiveIslandLogic.sectorSeconds(time), seconds.isFinite, seconds > 0 else { continue }
            var laps = recentLiveLaps[incomingSeries]?[driver.number] ?? []
            if let previous = laps.last {
                // A lap-count update can arrive before its matching time update.
                if previous.number <= number, previous.time == time { continue }
                if previous.number >= number { laps.removeAll { $0.number >= number } }
            }
            laps.append(LiveCompletedLap(number: number, time: time))
            recentLiveLaps[incomingSeries, default: [:]][driver.number] = Array(laps.suffix(2))
        }
    }

    func updateActivity() {
        activity.update(snapshot: liveSnapshot, mode: islandMode, favorite: favoriteLiveDriver,
                        favoriteName: favoriteStanding?.driverName, selectedNumbers: islandBattleNumbers, season: liveArtSeason)
    }

    var liveArtSeason: Int {
        if liveSnapshot.sourceMode == .replay { return season }
        return Calendar(identifier: .gregorian).component(.year, from: .now)
    }

    func refreshLiveActivityWhenLeavingForeground() {
        guard activity.activeSeries != nil, liveServerURL != nil else { return }
        scheduleLiveActivityRefresh()
        let application = UIApplication.shared
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        let refresh = Task { @MainActor in
            defer {
                if backgroundTask != .invalid {
                    application.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
            }
            await refreshLiveActivityInBackground(scheduleNext: false)
        }
        backgroundTask = application.beginBackgroundTask(withName: "Live Activity timing refresh") {
            refresh.cancel()
            if backgroundTask != .invalid {
                application.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
    }

    func scheduleLiveActivityRefresh() {
        guard activity.activeSeries != nil, liveServerURL != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.activityRefreshIdentifier)
        request.earliestBeginDate = .now.addingTimeInterval(60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func refreshLiveActivityInBackground(scheduleNext: Bool = true) async {
        guard !Task.isCancelled, let activeSeries = activity.activeSeries, let liveServerURL else { return }
        if scheduleNext { scheduleLiveActivityRefresh() }
        let context = dataContext
        guard var snapshot = try? await APIClient(baseURL: liveServerURL).liveActivitySnapshot(token: currentToken, series: activeSeries),
              !Task.isCancelled, context == dataContext, activity.activeSeries == activeSeries else { return }
        snapshot.series = activeSeries.rawValue
        let favoriteName = favoriteStanding?.driverName ?? activity.activeFavoriteName
        let favorite = favoriteName.flatMap { name in
            snapshot.drivers.first {
                LiveIslandLogic.rosterID(for: $0, favorites: [.init(id: "favorite", name: name)]) != nil
            }
        }
        activity.update(snapshot: snapshot, mode: islandMode, favorite: favorite, favoriteName: favoriteName,
                        selectedNumbers: islandBattleNumbers, season: liveArtSeason, existingOnly: true)
        await activity.waitForLastUpdate()
        if activity.activeSeries == nil {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.activityRefreshIdentifier)
        }
    }
    func endLiveActivity() {
        activity.end()
    }
}

private extension SessionType {
    var liveEntryDuration: TimeInterval {
        switch self {
        case .race: 3 * 3600
        case .sprint: 90 * 60
        case .sprintQualifying, .qualifying, .fp1, .fp2, .fp3: 2 * 3600
        }
    }
}
