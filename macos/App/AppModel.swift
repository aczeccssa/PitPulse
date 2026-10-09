import Foundation

enum AppConnectionStatus: Equatable, Sendable {
    case idle
    case loading
    case connected
    case stale
    case offline
    case requiresToken
    case failed
}

@MainActor
final class AppModel: ObservableObject {
    static let refreshInterval: TimeInterval = 15 * 60
    static let staleCacheInterval: TimeInterval = 6 * 60 * 60

    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var meta: ResponseMeta?
    @Published private(set) var connectionStatus: AppConnectionStatus = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSuccessfulLoadAt: Date?
    @Published private(set) var lastSuccessfulAttemptAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var selectedSeason: Int
    @Published private(set) var serverAddress: String
    @Published private(set) var isTokenStored = false
    @Published private(set) var settingsMessage: String?

    private let defaults: UserDefaults
    private let credentials: any CredentialStore
    private let cache: DiskCalendarCache
    private var generation = 0
    private let session: URLSession
    private var configuredServer: ServerAddress?
    private var nextMeetingOverride: Meeting?
    private var didBootstrap = false

    init(
        defaults: UserDefaults = .standard,
        credentials: any CredentialStore = KeychainStore(),
        cache: DiskCalendarCache = DiskCalendarCache(),
        session: URLSession = .shared,
        autoBootstrap: Bool = true
    ) {
        self.defaults = defaults
        self.credentials = credentials
        self.cache = cache
        self.session = session

        let savedAddress = defaults.string(forKey: PreferenceKeys.serverAddress)
        let fallbackAddress = "http://localhost:38701"
        let address = savedAddress ?? fallbackAddress
        self.serverAddress = address
        self.configuredServer = try? ServerAddress(rawValue: address)

        let currentYear = Calendar.current.component(.year, from: Date())
        self.selectedSeason = defaults.object(forKey: PreferenceKeys.selectedSeason) as? Int ?? currentYear

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

    var isShowingCachedData: Bool {
        guard let lastSuccessfulLoadAt else { return false }
        return Date().timeIntervalSince(lastSuccessfulLoadAt) > Self.staleCacheInterval
    }

    var statusSymbol: AppSymbol {
        StatusSymbolResolver.symbol(for: connectionStatus)
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await loadCachedIfAvailable()
        await refreshTokenStatus()
        await refreshNow()
    }

    func popupDidAppear() {
        if !didBootstrap {
            Task { await bootstrap() }
            return
        }
        if let lastSuccessfulAttemptAt,
           Date().timeIntervalSince(lastSuccessfulAttemptAt) < Self.refreshInterval {
            return
        }
        refresh(force: true)
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
            await performRefresh(server: server, season: season)
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
            await loadCachedIfAvailable()
            await performRefresh(server: configuredServer, season: season)
        }
    }

    @discardableResult
    func updateServerAddress(_ rawValue: String) -> Bool {
        do {
            let server = try ServerAddress(rawValue: rawValue)
            invalidateConnection()
            serverAddress = server.url.absoluteString
            configuredServer = server
            defaults.set(serverAddress, forKey: PreferenceKeys.serverAddress)
            meetings = []
            meta = nil
            nextMeetingOverride = nil
            errorMessage = nil
            settingsMessage = "服务器已更新"
            Task {
                await loadCachedIfAvailable()
                await refreshTokenStatus()
                await performRefresh(server: server, season: selectedSeason)
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
            settingsMessage = "Token 已删除"
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
        await performRefresh(server: configuredServer, season: selectedSeason)
    }

    private func invalidateConnection() {
        generation += 1
        lastSuccessfulLoadAt = nil
        lastSuccessfulAttemptAt = nil
        isRefreshing = false
        isTokenStored = false
        connectionStatus = .idle
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
            lastSuccessfulLoadAt = Date()
            lastSuccessfulAttemptAt = Date()
            errorMessage = nil
            connectionStatus = calendarResponse.meta.stale ? .stale : .connected
            isTokenStored = token != nil
            do {
                try await cache.save(server: server.url, season: season, envelope: calendarResponse)
            } catch {
                if requestGeneration == generation {
                    settingsMessage = "数据已读取，但缓存写入失败：\(error.localizedDescription)"
                }
            }
        } catch {
            guard requestGeneration == generation else { return }
            errorMessage = error.localizedDescription
            if error as? APIClientError == .unauthorized {
                connectionStatus = .requiresToken
            } else if meetings.isEmpty {
                connectionStatus = .failed
            } else {
                connectionStatus = .stale
            }
        }
        if requestGeneration == generation { isRefreshing = false }
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

enum PreferenceKeys {
    static let serverAddress = "serverAddress"
    static let selectedSeason = "selectedSeason"
}
