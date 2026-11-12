import Foundation
import SwiftUI
import SharedData

@MainActor
final class MobileModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(Date)
        case failed(String)

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }

        var lastLoaded: Date? {
            if case let .loaded(date) = self { return date }
            return nil
        }

        var errorText: String? {
            if case let .failed(message) = self { return message }
            return nil
        }
    }

    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var liveSnapshot = LiveSnapshot.disconnected()
    @Published private(set) var liveConnecting = false
    @Published private(set) var healthText: String?
    @Published private(set) var liveHistory: [String: [LiveTelemetry]] = [:]

    @Published var season: Int {
        didSet { defaults.set(season, forKey: PreferenceKeys.selectedSeason); invalidateCalendar() }
    }

    @Published var serverText: String {
        didSet {
            defaults.set(serverText, forKey: PreferenceKeys.serverAddress)
            if oldValue != serverText { invalidateCalendar(); if liveStarted { startLive() } }
        }
    }

    @Published private(set) var series: LiveSeries = .f1
    @Published private(set) var liveSnapshots: [LiveSeries: LiveSnapshot] = [:]
    @Published private(set) var driverRoster: [DriverStanding] = []
    @Published private(set) var rosterLoadError: String?
    @Published var settingsPresented = false
    @Published var liveNotice: String?
    @Published var favoriteDriverID: String? {
        didSet {
            defaults.set(favoriteDriverID, forKey: PreferenceKeys.favoriteDriverId)
            publishFavoriteWidget()
            updateActivity()
        }
    }
    @Published var islandMode: IslandContentMode {
        didSet { defaults.set(islandMode.rawValue, forKey: "mobileIslandMode"); updateActivity() }
    }
    @Published private(set) var islandBattleNumbers: [String] = []
    func toggleIslandBattle(_ number: String) {
        islandBattleNumbers = IslandBattleSelection.toggled(number, in: islandBattleNumbers)
        islandMode = .battle
    }
    func resetIslandBattle() { islandBattleNumbers = []; updateActivity() }
    private let liveStores: [LiveSeries: LiveStore] = [.f1: LiveStore(), .wec: LiveStore()]
    private var historiesBySeries: [LiveSeries: [String: [LiveTelemetry]]] = [:]
    private var liveConnectionContext: String?

    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "com.pitpulse.mobile")
    private let cache = DiskCalendarCache()
    private let activity = LiveActivityController()
    private var liveStarted = false
    private var calendarRequestID = UUID()
    private let widgetPublisher = WidgetSnapshotPublisher()
    private var widgetHighlightsContext: String?
    private var rosterSavedAt: Date = .distantPast
    private var recentRaceSources: [FavoriteRaceSource] = []
    private var recentRaceSavedAt: Date = .distantPast
    @Published private var credentialRevision = 0

    var dataContext: String { "\(serverURL?.absoluteString ?? serverText)|\(season)|\(credentialRevision)" }

    private func invalidateCalendar() {
        calendarRequestID = UUID()
        meetings = []
        loadState = .idle
        healthText = nil
        liveHistory = [:]
        driverRoster = []
        historiesBySeries = [:]
        liveSnapshots = [:]
        widgetHighlightsContext = nil
        rosterSavedAt = .distantPast
        recentRaceSources = []
        recentRaceSavedAt = .distantPast
        widgetPublisher.clear()
    }

    init() {
        let storedSeason = defaults.integer(forKey: PreferenceKeys.selectedSeason)
        let storedServer = defaults.string(forKey: PreferenceKeys.serverAddress)
        favoriteDriverID = defaults.string(forKey: PreferenceKeys.favoriteDriverId)
        islandMode = defaults.string(forKey: "mobileIslandMode").flatMap(IslandContentMode.init(rawValue:)) ?? .overview
        season = storedSeason > 2000 ? storedSeason : Calendar.current.component(.year, from: Date())
        serverText = storedServer?.isEmpty == false ? storedServer! : "http://localhost:38701"
        for (series, store) in liveStores {
            store.onSnapshot = { [weak self] snapshot in self?.handle(snapshot, from: series) }
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["PITPULSE_DEMO_ACTIVITY"] == "1" {
            activity.demoStart()
        }
        #endif
    }

    var serverURL: URL? {
        try? ServerAddress(rawValue: serverText).url
    }

    var currentToken: String? {
        guard let serverURL else { return nil }
        return try? keychain.token(for: serverURL)
    }

    var hasToken: Bool {
        (currentToken?.isEmpty == false)
    }

    var isLiveRunning: Bool { liveStarted }

    var sortedDrivers: [LiveDriver] {
        liveSnapshot.drivers.sorted {
            let left = $0.position ?? $0.classPosition ?? Int.max
            let right = $1.position ?? $1.classPosition ?? Int.max
            return left == right ? $0.number < $1.number : left < right
        }
    }

    // MARK: Calendar

    func loadCalendar(force: Bool = false) async {
        guard let serverURL else {
            loadState = .failed(APIClientError.invalidServerAddress(serverText).localizedDescription)
            return
        }
        if !force, loadState.lastLoaded != nil { return }
        let context = dataContext
        let selectedSeason = season
        let requestID = UUID()
        calendarRequestID = requestID
        if meetings.isEmpty, let cached = try? await cache.load(server: serverURL, season: selectedSeason) {
            guard dataContext == context, calendarRequestID == requestID, !Task.isCancelled else { return }
            meetings = cached.envelope.data.sorted { $0.startDate < $1.startDate }
            publishWidget(savedAt: cached.envelope.meta.stale ? .distantPast : cached.savedAt)
        }
        loadState = .loading
        do {
            let envelope = try await APIClient(baseURL: serverURL).calendar(season: selectedSeason, token: currentToken)
            guard dataContext == context, calendarRequestID == requestID, !Task.isCancelled else { return }
            meetings = envelope.data.sorted { $0.startDate < $1.startDate }
            loadState = meetings.isEmpty
                ? .failed("当前服务器尚无 \(selectedSeason) 赛季 F1 赛历。请检查服务地址或服务器同步状态。")
                : .loaded(Date())
            publishWidget(savedAt: envelope.meta.stale ? .distantPast : (envelope.meta.fetchedAt ?? .distantPast))
            try? await cache.save(server: serverURL, season: selectedSeason, envelope: envelope)
        } catch {
            guard dataContext == context, calendarRequestID == requestID, !Task.isCancelled else { return }
            loadState = .failed((meetings.isEmpty ? "" : "缓存数据 · ") + Self.message(for: error))
        }
    }

    private func publishWidget(savedAt: Date = .now) {
        widgetPublisher.publishCalendar(meetings: meetings, savedAt: savedAt)
    }

    /// Publishes the most recent completed races for the post-race and favorite-driver widgets.
    /// Widgets never fetch; a missing result leaves the previous honest snapshot in place.
    func loadWidgetHighlights(force: Bool = false) async {
        guard let serverURL else { return }
        let races = completedRaces(limit: 3)
        guard let newest = races.first else { return }
        let baseContext = dataContext
        let context = "\(baseContext)|" + races.map(\.session.id).joined(separator: ",")
        guard force || widgetHighlightsContext != context else { return }
        let client = APIClient(baseURL: serverURL)
        var sources: [FavoriteRaceSource] = []
        for race in races {
            do {
                let response = try await client.sessionResults(sessionId: race.session.id, token: currentToken)
                guard baseContext == dataContext, !Task.isCancelled else { return }
                guard !response.data.isEmpty else { continue }
                sources.append(FavoriteRaceSource(meeting: race.meeting, session: race.session,
                    results: response.data,
                    savedAt: response.meta.stale ? .distantPast : (response.meta.fetchedAt ?? .now)))
            } catch {
                continue
            }
        }
        guard let newestSource = sources.first(where: { $0.session.id == newest.session.id }) else { return }
        widgetHighlightsContext = context
        recentRaceSources = sources
        recentRaceSavedAt = sources.contains { $0.savedAt == .distantPast }
            ? .distantPast
            : (sources.map(\.savedAt).max() ?? .distantPast)
        // Results are enough for the podium, fastest lap and distance. Safety-car
        // periods need the much heavier analysis payload, so the widget omits them
        // rather than making every launch download telemetry.
        widgetPublisher.publishLastRace(meeting: newestSource.meeting, session: newestSource.session,
            results: newestSource.results, savedAt: newestSource.savedAt)
        publishFavoriteWidget()
    }

    private func completedRaces(limit: Int) -> [(meeting: Meeting, session: Session)] {
        let now = Date()
        let races = meetings
            .compactMap { meeting -> (Meeting, Session)? in
                let race = meeting.sessions
                    .filter { $0.sessionType == .race && $0.status != .cancelled && $0.status != .postponed }
                    .filter { session in
                        if session.status == .finished { return true }
                        guard session.status != .live else { return false }
                        let end = session.endTime ?? session.startTime.addingTimeInterval(3 * 3600)
                        return end < now
                    }
                    .max { $0.startTime < $1.startTime }
                return race.map { (meeting, $0) }
            }
            .sorted { $0.1.startTime > $1.1.startTime }
        return Array(races.prefix(limit))
    }

    // MARK: Live

    var availableLiveSeries: [LiveSeries] {
        LiveSeries.allCases.filter { liveSnapshots[$0].map { LiveSessionAvailability.isAvailable($0) } ?? false }
    }
    var hasActiveLive: Bool { !availableLiveSeries.isEmpty }
    var favoriteStanding: DriverStanding? { driverRoster.first { $0.id == favoriteDriverID } }
    var favoriteLiveDriver: LiveDriver? {
        guard let favoriteDriverID else { return nil }
        return liveSnapshot.drivers.first { driverID(for: $0) == favoriteDriverID }
    }

    func driverID(for driver: LiveDriver) -> String? {
        guard !liveSnapshot.isWec else { return nil }
        let roster = driverRoster.map { FavoriteDriver(id: $0.id, name: $0.driverName) }
        if let exact = LiveIslandLogic.rosterID(for: driver, favorites: roster) { return exact }
        guard let surname = driver.name?.split(whereSeparator: \.isWhitespace).last else { return nil }
        let key = LiveIslandLogic.assetSlug(String(surname))
        let matches = driverRoster.filter { LiveIslandLogic.assetSlug(String($0.driverName.split(whereSeparator: \.isWhitespace).last ?? "")) == key }
        return matches.count == 1 ? matches[0].id : nil
    }
    func helmetAsset(for driver: LiveDriver) -> String {
        MotorsportAssetName.helmetName(driverID: driverID(for: driver), name: driver.name ?? "", season: season)
    }

    func loadF1Roster(force: Bool = false) async {
        guard force || driverRoster.isEmpty, let serverURL else { return }
        let context = dataContext
        rosterLoadError = nil
        do {
            let response = try await APIClient(baseURL: serverURL).driverStandings(season: season, token: currentToken)
            guard context == dataContext, !Task.isCancelled else { return }
            driverRoster = response.data
            rosterLoadError = driverRoster.isEmpty ? "当前服务器暂无 F1 车手数据，请检查服务地址。" : nil
            let savedAt = response.meta.stale ? .distantPast : (response.meta.fetchedAt ?? .now)
            widgetPublisher.publishStandings(response.data, season: season, savedAt: savedAt)
            rosterSavedAt = savedAt
            publishFavoriteWidget()
            updateActivity()
        } catch { if !Task.isCancelled { rosterLoadError = Self.message(for: error) } }
    }

    private func publishFavoriteWidget() {
        guard let favoriteDriverID else {
            widgetPublisher.publishFavoriteDriver([], favoriteID: nil, season: season, savedAt: rosterSavedAt)
            return
        }
        guard !driverRoster.isEmpty else { return }
        let savedAt = recentRaceSources.isEmpty ? rosterSavedAt : min(rosterSavedAt, recentRaceSavedAt)
        widgetPublisher.publishFavoriteDriver(driverRoster, favoriteID: favoriteDriverID,
            season: season, savedAt: savedAt, recentRaces: recentRaceSources)
    }

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

    private func handle(_ snapshot: LiveSnapshot, from incomingSeries: LiveSeries) {
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

    private func updateActivity() {
        activity.update(snapshot: liveSnapshot, mode: islandMode, favorite: favoriteLiveDriver, favoriteName: favoriteStanding?.driverName, selectedNumbers: islandBattleNumbers)
    }

    private func publishLiveWidget(_ snapshot: LiveSnapshot) {
        widgetPublisher.publishLive(snapshot)
    }

    func endLiveActivity() {
        activity.end()
    }

    // MARK: Settings

    @discardableResult
    func saveConnection(address: String, token: String) -> String? {
        guard let address = try? ServerAddress(rawValue: address) else { return "请填写有效的服务器地址。" }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            do { try keychain.save(token: token, for: address.url) }
            catch { return Self.message(for: error) }
        }
        serverText = address.url.absoluteString
        credentialRevision += 1
        invalidateCalendar()
        if liveStarted { startLive() }
        return nil
    }

    @discardableResult
    func saveToken(_ token: String) -> String? {
        guard let serverURL else { return "请先填写有效的服务器地址。" }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? keychain.deleteToken(for: serverURL)
            return nil
        }
        do {
            try keychain.save(token: trimmed, for: serverURL)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func testConnection() async {
        guard let serverURL else {
            healthText = "服务器地址无效"
            return
        }
        healthText = "连接中…"
        do {
            let client = APIClient(baseURL: serverURL)
            let response = try await client.health(token: currentToken)
            async let calendar = client.calendar(season: season, token: currentToken)
            async let drivers = client.driverStandings(season: season, token: currentToken)
            async let teams = client.constructorStandings(season: season, token: currentToken)
            let counts = try await (calendar.data.count, drivers.data.count, teams.data.count)
            healthText = "服务 \(response.status) · F1 赛历 \(counts.0) 场 / 车手 \(counts.1) 位 / 车队 \(counts.2) 支"
            if counts.0 == 0 || counts.1 == 0 || counts.2 == 0 {
                healthText! += "\n当前服务器的 F1 数据未同步完整；连接成功不代表已有赛事数据。"
            }
        } catch {
            healthText = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
