import AppKit
import Combine
import Foundation
import SharedData

@MainActor
final class AppModel: ObservableObject {
    static let refreshInterval: TimeInterval = 15 * 60
    static let staleCacheInterval: TimeInterval = 6 * 60 * 60

    @Published var meetings: [Meeting] = []
    @Published var meta: ResponseMeta?
    @Published var sessionResults: [SessionResult] = []
    @Published var resultMeta: ResponseMeta?
    @Published var resultError: String?
    @Published var selectedResultSessionID: String?
    @Published var driverStandings: [DriverStanding] = []
    @Published var constructorStandings: [ConstructorStanding] = []
    @Published var standingsMeta: ResponseMeta?
    @Published var standingsError: String?
    @Published var showingConstructorStandings = false
    @Published var connectionStatus: AppConnectionStatus = .idle
    @Published var errorMessage: String?
    @Published var lastSuccessfulLoadAt: Date?
    @Published var lastSuccessfulAttemptAt: Date?
    @Published var isRefreshing = false
    @Published var selectedSeason: Int
    @Published var serverAddress: String
    @Published var isTokenStored = false
    @Published var settingsMessage: String?
    @Published var remindersEnabled = false
    @Published var reminderMinutes = 15
    @Published var reminderMessage: String?
    @Published var reminderPermissionDenied = false
    @Published var favoriteDriverId: String?
    @Published var favoriteWecDriverId: String?
    @Published var favoriteWecDriverName: String?
    @Published var notchAutoShowEnabled: Bool
    @Published var notchCollapseOnMouseExit: Bool
    @Published var liveSeries: LiveSeries

    let widgetPublisher: WidgetSnapshotPublisher?
    var widgetSubscription: AnyCancellable?
    var widgetStandings: [DriverStanding] = []
    var widgetStandingsSavedAt = Date.distantPast
    var widgetRecentRaces: [FavoriteRaceSource] = []
    var widgetHighlightsKey: String?
    var widgetHighlightsLoadedAt: Date?
    let defaults: UserDefaults
    let credentials: any CredentialStore
    let cache: DiskCalendarCache
    let reminderCenter: any SessionReminderCenter
    let networkMonitor: any NetworkPathMonitoring
    let liveStore = LiveStore()
    let mapStore = MapStore()
    let retryDelays: [TimeInterval]
    var generation = 0
    var resultGeneration = 0
    var standingsGeneration = 0
    let session: URLSession
    let popupRefreshInterval: TimeInterval
    var configuredServer: ServerAddress?
    var nextMeetingOverride: Meeting?
    var didBootstrap = false
    var workspaceObservers: [NSObjectProtocol] = []
    var popupRefreshTask: Task<Void, Never>?
    var retryTask: Task<Void, Never>?
    var activeRefreshTask: Task<Void, Never>?
    var activeRefreshID: UUID?
    var manualRefreshTask: Task<Void, Never>?
    var manualRefreshID: UUID?
    var isManualRefreshActive = false
    var retryAttempt = 0
    var networkAvailable = true

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
}
