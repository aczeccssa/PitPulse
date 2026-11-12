import AppKit
import Combine
import Foundation
import SharedData

@MainActor
final class AppModel: ObservableObject {
    static let refreshInterval: TimeInterval = 15 * 60
    static let staleCacheInterval: TimeInterval = 6 * 60 * 60

    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var meta: ResponseMeta?
    @Published private(set) var sessionResults: [SessionResult] = []
    @Published private(set) var resultMeta: ResponseMeta?
    @Published private(set) var resultError: String?
    @Published private(set) var selectedResultSessionID: String?
    @Published private(set) var driverStandings: [DriverStanding] = []
    @Published private(set) var constructorStandings: [ConstructorStanding] = []
    @Published private(set) var standingsMeta: ResponseMeta?
    @Published private(set) var standingsError: String?
    @Published private(set) var showingConstructorStandings = false
    @Published private(set) var connectionStatus: AppConnectionStatus = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSuccessfulLoadAt: Date?
    @Published private(set) var lastSuccessfulAttemptAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var selectedSeason: Int
    @Published private(set) var serverAddress: String
    @Published private(set) var isTokenStored = false
    @Published private(set) var settingsMessage: String?
    @Published private(set) var remindersEnabled = false
    @Published private(set) var reminderMinutes = 15
    @Published private(set) var reminderMessage: String?
    @Published private(set) var reminderPermissionDenied = false
    @Published private(set) var favoriteDriverId: String?
    @Published private(set) var favoriteWecDriverId: String?
    @Published private(set) var favoriteWecDriverName: String?
    @Published private(set) var notchAutoShowEnabled: Bool
    @Published private(set) var notchCollapseOnMouseExit: Bool
    @Published private(set) var liveSeries: LiveSeries

    private let widgetPublisher: WidgetSnapshotPublisher?
    private var widgetSubscription: AnyCancellable?
    private var widgetStandings: [DriverStanding] = []
    private var widgetStandingsSavedAt = Date.distantPast
    private var widgetRecentRaces: [FavoriteRaceSource] = []
    private var widgetHighlightsKey: String?
    private var widgetHighlightsLoadedAt: Date?
    private let defaults: UserDefaults
    private let credentials: any CredentialStore
    private let cache: DiskCalendarCache
    private let reminderCenter: any SessionReminderCenter
    private let networkMonitor: any NetworkPathMonitoring
    let liveStore = LiveStore()
    let mapStore = MapStore()
    private let retryDelays: [TimeInterval]
    private var generation = 0
    private var resultGeneration = 0
    private var standingsGeneration = 0
    private let session: URLSession
    private let popupRefreshInterval: TimeInterval
    private var configuredServer: ServerAddress?
    private var nextMeetingOverride: Meeting?
    private var didBootstrap = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var popupRefreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var activeRefreshTask: Task<Void, Never>?
    private var activeRefreshID: UUID?
    private var manualRefreshTask: Task<Void, Never>?
    private var manualRefreshID: UUID?
    private var isManualRefreshActive = false
    private var retryAttempt = 0
    private var networkAvailable = true

    init(
        defaults: UserDefaults = .standard,
        credentials: any CredentialStore = KeychainStore(),
        cache: DiskCalendarCache = DiskCalendarCache(),
        reminderCenter: (any SessionReminderCenter)? = nil,
        networkMonitor: (any NetworkPathMonitoring)? = nil,
        session: URLSession = .shared,
        popupRefreshInterval: TimeInterval = AppModel.refreshInterval,
        retryDelays: [TimeInterval] = [5, 15, 30, 60, 300],
        autoBootstrap: Bool = true,
        widgetPublisher: WidgetSnapshotPublisher? = nil
    ) {
        self.widgetPublisher = widgetPublisher ?? (autoBootstrap ? WidgetSnapshotPublisher() : nil)
        self.defaults = defaults
        self.credentials = credentials
        self.cache = cache
        self.reminderCenter = reminderCenter ?? UserNotificationReminderCenter()
        self.networkMonitor = networkMonitor ?? SystemNetworkPathMonitor()
        self.session = session
        self.popupRefreshInterval = max(popupRefreshInterval, 0.001)
        self.retryDelays = retryDelays.isEmpty ? [5, 15, 30, 60, 300] : retryDelays
        self.remindersEnabled = defaults.bool(forKey: PreferenceKeys.remindersEnabled)
        let savedMinutes = defaults.object(forKey: PreferenceKeys.reminderMinutes) as? Int ?? 15
        self.reminderMinutes = SessionReminderPlanner.allowedMinutes.contains(savedMinutes) ? savedMinutes : 15
        self.favoriteDriverId = defaults.string(forKey: PreferenceKeys.favoriteDriverId)
        self.favoriteWecDriverId = defaults.string(forKey: PreferenceKeys.favoriteWecDriverId)
        self.favoriteWecDriverName = defaults.string(forKey: PreferenceKeys.favoriteWecDriverName)
        self.notchAutoShowEnabled = defaults.object(forKey: PreferenceKeys.notchAutoShowEnabled) == nil
            ? true : defaults.bool(forKey: PreferenceKeys.notchAutoShowEnabled)
        self.notchCollapseOnMouseExit = defaults.bool(forKey: PreferenceKeys.notchCollapseOnMouseExit)
        self.liveSeries = LiveSeries(rawValue: defaults.string(forKey: PreferenceKeys.liveSeries) ?? "") ?? .f1

        let savedAddress = defaults.string(forKey: PreferenceKeys.serverAddress)
        let fallbackAddress = "http://localhost:38701"
        let address = savedAddress ?? fallbackAddress
        self.serverAddress = address
        self.configuredServer = try? ServerAddress(rawValue: address)

        let currentYear = Calendar.current.component(.year, from: Date())
        self.selectedSeason = defaults.object(forKey: PreferenceKeys.selectedSeason) as? Int ?? currentYear
        self.widgetSubscription = liveStore.$snapshot.sink { [weak self] snapshot in
            guard let self, self.liveSeries == .f1 else { return }
            self.widgetPublisher?.publishLive(snapshot)
        }
        self.liveStore.onDataRefresh = { [weak self] event in
            Task { @MainActor [weak self] in await self?.handleDataRefresh(event) }
        }
        self.liveStore.onStreamConnected = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshCalendar()
                await self.refreshPageData()
            }
        }
        self.workspaceObservers = [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification].map { name in
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if name == NSWorkspace.willSleepNotification { self?.prepareForSleep() }
                    else { await self?.resumeAfterWake() }
                }
            }
        }
        self.networkMonitor.start { [weak self] isAvailable in
            Task { @MainActor [weak self] in self?.networkPathDidChange(isAvailable: isAvailable) }
        }

        if autoBootstrap {
            Task { [weak self] in
                await self?.bootstrap()
            }
        }
    }

    var serverURL: URL? {
        configuredServer?.url
    }

    var nextSession: NextSession? {
        if let nextMeetingOverride,
           let session = CalendarLogic.nextSession(in: [nextMeetingOverride], now: Date())?.session {
            return NextSession(meeting: nextMeetingOverride, session: session)
        }
        return CalendarLogic.nextSession(in: meetings, now: Date())
    }

    var nextMeeting: Meeting? {
        nextSession?.meeting
    }

    var currentIslandSession: NextSession? {
        LiveIslandLogic.currentScheduledSession(in: meetings, now: Date())
    }

    func plannedIslandSessionLabel(for snapshot: LiveSnapshot, now: Date = Date()) -> String {
        if let currentIslandSession = LiveIslandLogic.currentScheduledSession(in: meetings, now: now) {
            return currentIslandSession.session.sessionType.displayName
        }
        if let nextSession = CalendarLogic.nextSession(in: meetings, now: now) {
            return "下次 \(nextSession.session.sessionType.displayName) · 还有 \(CalendarLogic.countdownText(until: nextSession.session.startTime, now: now))"
        }
        return "暂无赛程"
    }

    var availableResultSessions: [NextSession] {
        meetings.flatMap { meeting in
            meeting.sessions
                .filter { $0.status != .cancelled && ($0.status == .finished || ($0.endTime ?? meeting.endDate) <= Date()) }
                .map { NextSession(meeting: meeting, session: $0) }
        }
        .sorted { ($0.session.endTime ?? $0.session.startTime) > ($1.session.endTime ?? $1.session.startTime) }
    }

    var isShowingCachedData: Bool {
        guard let lastSuccessfulLoadAt else { return false }
        return Date().timeIntervalSince(lastSuccessfulLoadAt) > Self.staleCacheInterval
    }

    var statusSymbol: AppSymbol {
        StatusSymbolResolver.symbol(for: connectionStatus)
    }

    var favoriteDrivers: [FavoriteDriver] {
        var names: [String: String] = [:]
        (driverStandings.map { ($0.driverId, $0.driverName) } + sessionResults.map { ($0.driverId, $0.driverName) })
            .forEach { names[$0.0] = $0.1 }
        if let favoriteDriverId, names[favoriteDriverId] == nil {
            names[favoriteDriverId] = favoriteDriverId
        }
        if let favoriteWecDriverId, names[favoriteWecDriverId] == nil {
            names[favoriteWecDriverId] = favoriteWecDriverName ?? favoriteWecDriverId
        }
        return names.map { FavoriteDriver(id: $0.key, name: $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await loadCachedIfAvailable()
        await refreshTokenStatus()
        if networkAvailable {
            startLiveStream()
            await refreshCalendar()
        }
        else { markOffline(); await refreshPageData() }
    }

    func popupDidAppear() {
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


    func sessionAnalysis(sessionID: String, driverID: String, season: Int, lap: Int?) async throws -> APIEnvelope<SessionAnalysis> {
        try await analysis(key: "analysis-\(sessionID)-\(driverID)-\(lap ?? 0)", season: season) { client, token in
            try await client.sessionAnalysis(sessionId: sessionID, driverId: driverID, lap: lap, token: token)
        }
    }

    func seasonAnalysis(kind: String, id: String, season: Int) async throws -> APIEnvelope<SeasonAnalysis> {
        try await analysis(key: "analysis-\(kind)-\(id)", season: season) { client, token in
            try await client.seasonAnalysis(kind: kind, id: id, season: season, token: token)
        }
    }

    func cachedAnalysis<Value: Codable & Sendable>(key: String, season: Int, as type: Value.Type) async -> APIEnvelope<Value>? {
        guard let server = configuredServer else { return nil }
        let value = try? await cache.load(server: server.url, season: season, key: key, as: type)
        guard server == configuredServer, !Task.isCancelled else { return nil }
        return value
    }

    private func analysis<Value: Codable & Sendable>(key: String, season: Int,
        fetch: (APIClient, String?) async throws -> APIEnvelope<Value>) async throws -> APIEnvelope<Value> {
        guard let server = configuredServer else { throw APIClientError.invalidServerAddress(serverAddress) }
        do {
            let token = try credentials.token(for: server.url)
            let value = try await fetch(APIClient(baseURL: server.url, session: session), token)
            try Task.checkCancellation()
            guard server == configuredServer else { throw CancellationError() }
            if value.meta.analysisCanBeCached {
                try? await cache.save(server: server.url, season: season, key: key, envelope: value)
            }
            return value
        } catch {
            if error is CancellationError { throw error }
            guard server == configuredServer else { throw CancellationError() }
            // Authorization failures must not expose a previous authenticated response.
            if let apiError = error as? APIClientError, apiError == .unauthorized { throw error }
            if let old = try? await cache.load(server: server.url, season: season, key: key, as: Value.self) {
                return APIEnvelope(data: old.data, meta: ResponseMeta(schemaVersion: old.meta.schemaVersion,
                    revision: old.meta.revision, stale: true, quality: old.meta.quality, source: old.meta.source,
                    fetchedAt: old.meta.fetchedAt, sourceUpdatedAt: old.meta.sourceUpdatedAt))
            }
            throw error
        }
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

    private func handleDataRefresh(_ event: DataRefreshEvent) async {
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

    private func setRefreshError(_ event: DataRefreshEvent, target: ManualRefreshTarget) {
        let message = event.status == .rateLimited
            ? "上游限流，稍后再试。\(event.retryAfter.map { "下次尝试：\($0)" } ?? "")"
            : "上游刷新失败，保留现有缓存。"
        switch target {
        case .calendar: errorMessage = message
        case .results: resultError = message
        case .standings: standingsError = message
        }
    }

    private func setRefreshError(_ error: Error, target: ManualRefreshTarget) {
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

    func selectSeason(_ season: Int) {
        guard season >= 2000, season <= Calendar.current.component(.year, from: Date()) + 3 else {
            return
        }
        guard season != selectedSeason else { return }
        invalidateConnection()
        selectedSeason = season
        defaults.set(season, forKey: PreferenceKeys.selectedSeason)
        meetings = []
        meta = nil
        nextMeetingOverride = nil
        errorMessage = nil
        Task {
            await reminderCenter.removeAllPending()
            await loadCachedIfAvailable()
            await refreshCalendar(server: configuredServer, season: season)
        }
    }

    @discardableResult
    func updateServerAddress(_ rawValue: String) -> Bool {
        do {
            let server = try ServerAddress(rawValue: rawValue)
            invalidateConnection()
            liveStore.stop(reason: "server_changed")
            serverAddress = server.url.absoluteString
            configuredServer = server
            defaults.set(serverAddress, forKey: PreferenceKeys.serverAddress)
            meetings = []
            meta = nil
            nextMeetingOverride = nil
            errorMessage = nil
            settingsMessage = "服务器已更新"
            Task {
                await reminderCenter.removeAllPending()
                await loadCachedIfAvailable()
                await refreshTokenStatus()
                startLiveStream()
                await refreshCalendar(server: server, season: selectedSeason)
            }
            return true
        } catch {
            settingsMessage = error.localizedDescription
            return false
        }
    }

    func saveToken(_ token: String) {
        guard let server = configuredServer else {
            settingsMessage = APIClientError.invalidServerAddress(serverAddress).localizedDescription
            return
        }
        do {
            try credentials.save(token: token, for: server.url)
            isTokenStored = true
            settingsMessage = "Token 已保存到 Keychain"
            retryAttempt = 0
            retryTask?.cancel()
            startLiveStream()
            refresh(force: true)
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func deleteToken() {
        guard let server = configuredServer else { return }
        do {
            try credentials.deleteToken(for: server.url)
            isTokenStored = false
            widgetPublisher?.clear()
            settingsMessage = "Token 已删除"
            retryAttempt = 0
            retryTask?.cancel()
            startLiveStream()
            refresh(force: true)
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func refreshTokenStatus() async {
        guard let server = configuredServer else {
            isTokenStored = false
            return
        }
        do {
            isTokenStored = try credentials.token(for: server.url) != nil
        } catch {
            isTokenStored = false
            settingsMessage = error.localizedDescription
        }
    }

    func testConnection() async {
        guard let server = configuredServer else {
            settingsMessage = APIClientError.invalidServerAddress(serverAddress).localizedDescription
            return
        }
        settingsMessage = "正在连接…"
        do {
            let token = try credentials.token(for: server.url)
            let client = APIClient(baseURL: server.url, session: session)
            let response = try await client.health(token: token)
            settingsMessage = response.database ? "连接成功，数据库可用" : "已连接，但数据库不可用"
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func clearCurrentCache() {
        guard let server = configuredServer else { return }
        Task {
            do {
                try await cache.clear(server: server.url)
                settingsMessage = "当前服务器缓存已清除"
            } catch {
                settingsMessage = error.localizedDescription
            }
        }
    }

    func refreshNow() async {
        await refreshCalendar()
    }

    func setRemindersEnabled(_ enabled: Bool) async {
        guard enabled else {
            remindersEnabled = false
            defaults.set(false, forKey: PreferenceKeys.remindersEnabled)
            reminderMessage = nil
            await reminderCenter.removeAllPending()
            return
        }

        do {
            let authorization = await reminderCenter.authorization()
            let allowed: Bool
            switch authorization {
            case .authorized:
                allowed = true
            case .denied:
                allowed = false
            case .notDetermined:
                allowed = try await reminderCenter.requestAuthorization()
            }
            guard allowed else {
                reminderPermissionDenied = true
                reminderMessage = "通知权限未开启；可在系统设置中允许 PitPulse 通知。"
                return
            }
            reminderPermissionDenied = false
            remindersEnabled = true
            defaults.set(true, forKey: PreferenceKeys.remindersEnabled)
            reminderMessage = "已开启全部 Session 提前 \(reminderMinutes) 分钟提醒。"
            if let configuredServer { await syncReminders(meetings, server: configuredServer, season: selectedSeason) }
        } catch {
            reminderMessage = "无法开启通知：\(error.localizedDescription)"
        }
    }

    func setReminderMinutes(_ minutes: Int) async {
        guard SessionReminderPlanner.allowedMinutes.contains(minutes) else { return }
        reminderMinutes = minutes
        defaults.set(minutes, forKey: PreferenceKeys.reminderMinutes)
        if remindersEnabled, let configuredServer {
            await syncReminders(meetings, server: configuredServer, season: selectedSeason)
        }
    }

    func favoriteDriverId(for series: LiveSeries) -> String? {
        series == .wec ? favoriteWecDriverId : favoriteDriverId
    }

    func setFavoriteDriver(_ id: String?, name: String? = nil, series: LiveSeries = .f1) {
        if series == .wec {
            favoriteWecDriverId = id
            // WEC drivers are not in the F1 roster, so keep a display name with the id.
            favoriteWecDriverName = id == nil ? nil : name
            if let id { defaults.set(id, forKey: PreferenceKeys.favoriteWecDriverId) }
            else { defaults.removeObject(forKey: PreferenceKeys.favoriteWecDriverId) }
            if let favoriteWecDriverName { defaults.set(favoriteWecDriverName, forKey: PreferenceKeys.favoriteWecDriverName) }
            else { defaults.removeObject(forKey: PreferenceKeys.favoriteWecDriverName) }
        } else {
            favoriteDriverId = id
            if let id { defaults.set(id, forKey: PreferenceKeys.favoriteDriverId) }
            else { defaults.removeObject(forKey: PreferenceKeys.favoriteDriverId) }
            publishFavoriteWidget()
        }
    }

    func setNotchAutoShowEnabled(_ enabled: Bool) {
        notchAutoShowEnabled = enabled
        defaults.set(enabled, forKey: PreferenceKeys.notchAutoShowEnabled)
    }

    func setNotchCollapseOnMouseExit(_ enabled: Bool) {
        notchCollapseOnMouseExit = enabled
        defaults.set(enabled, forKey: PreferenceKeys.notchCollapseOnMouseExit)
    }

    func setLiveSeries(_ series: LiveSeries) {
        guard series != liveSeries else { return }
        widgetPublisher?.clearLive()
        liveSeries = series
        defaults.set(series.rawValue, forKey: PreferenceKeys.liveSeries)
        if didBootstrap {
            startLiveStream()
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

    private func publishWidgetStandings(_ standings: [DriverStanding], meta: ResponseMeta) {
        widgetStandings = standings
        widgetStandingsSavedAt = meta.stale ? .distantPast : (meta.fetchedAt ?? .distantPast)
        widgetPublisher?.publishStandings(standings, season: selectedSeason, savedAt: widgetStandingsSavedAt)
        publishFavoriteWidget()
    }

    private func publishFavoriteWidget() {
        let savedAt = ([widgetStandingsSavedAt] + widgetRecentRaces.map(\.savedAt)).min() ?? .distantPast
        widgetPublisher?.publishFavoriteDriver(widgetStandings, favoriteID: favoriteDriverId,
            season: selectedSeason, savedAt: savedAt, recentRaces: widgetRecentRaces)
    }

    private func refreshWidgetHighlights() async {
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

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
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

    private func prepareForSleep() {
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

    private func resumeAfterWake() async {
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

    private func startLiveStream() {
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

    private func markOffline() {
        connectionStatus = .offline
        if meetings.isEmpty { lastSuccessfulLoadAt = nil }
    }

    private func refreshCalendar(server: ServerAddress? = nil, season: Int? = nil) async {
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

    private func invalidateConnection() {
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

    private func startPopupRefresh() {
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

    private func performRefresh(server: ServerAddress?, season: Int) async {
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

    private func scheduleRetry(for error: Error) {
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

    private func syncReminders(_ meetings: [Meeting], server: ServerAddress, season: Int) async {
        guard remindersEnabled else { return }
        let desired = SessionReminderPlanner.reminders(
            meetings: meetings, serverIdentity: server.identity, season: season,
            minutesBefore: reminderMinutes, now: Date()
        )
        do {
            for reminder in desired { try await reminderCenter.schedule(reminder) }
            let desiredIDs = Set(desired.map(\.identifier))
            let staleIDs = (await reminderCenter.pendingIdentifiers()).filter {
                $0.hasPrefix("pitpulse.") && !desiredIDs.contains($0)
            }
            await reminderCenter.removePending(identifiers: staleIDs)
            reminderMessage = nil
        } catch {
            reminderMessage = "提醒安排失败：\(error.localizedDescription)"
        }
    }

    private func loadResultsCache(sessionID: String, requestGeneration: Int? = nil) async {
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

    private func loadStandingsCache(server: ServerAddress, season: Int, isConstructor: Bool, requestGeneration: Int) async {
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

    private func loadCachedIfAvailable() async {
        guard let server = configuredServer else { return }
        let season = selectedSeason
        let cacheGeneration = generation
        do {
            let cached = try await cache.load(server: server.url, season: season)
            guard cacheGeneration == generation,
                  server == configuredServer, season == selectedSeason else { return }
            if let cached {
                meetings = cached.envelope.data
                meta = cached.envelope.meta
                widgetPublisher?.publishCalendar(meetings: meetings, savedAt: cached.envelope.meta.stale ? .distantPast : cached.savedAt)
                lastSuccessfulLoadAt = cached.savedAt
                // Cached content is not a successful connection in this process.
                nextMeetingOverride = nil
                connectionStatus = Date().timeIntervalSince(cached.savedAt) > Self.staleCacheInterval
                    ? .offline
                    : .stale
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func validServerNextMeeting(_ meeting: Meeting?) -> Meeting? {
        guard let meeting,
              CalendarLogic.nextSession(in: [meeting], now: Date()) != nil
        else {
            return nil
        }
        return meeting
    }

}

