import Foundation
import SwiftUI
import PitPulseData
import PitPulseShared

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

    @Published var season: Int {
        didSet { defaults.set(season, forKey: PreferenceKeys.selectedSeason) }
    }

    @Published var serverText: String {
        didSet { defaults.set(serverText, forKey: PreferenceKeys.serverAddress) }
    }

    @Published var series: LiveSeries {
        didSet {
            defaults.set(series.rawValue, forKey: PreferenceKeys.liveSeries)
            if liveStarted { startLive() }
        }
    }

    let liveStore = LiveStore()

    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "com.pitpulse.mobile")
    private let cache = DiskCalendarCache()
    private let activity = LiveActivityController()
    private var liveStarted = false
    private var autoStartAttempted = false

    init() {
        let storedSeason = defaults.integer(forKey: PreferenceKeys.selectedSeason)
        let storedServer = defaults.string(forKey: PreferenceKeys.serverAddress)
        let storedSeries = defaults.string(forKey: PreferenceKeys.liveSeries)
        season = storedSeason > 2000 ? storedSeason : Calendar.current.component(.year, from: Date())
        serverText = storedServer?.isEmpty == false ? storedServer! : "http://localhost:38701"
        series = storedSeries.flatMap(LiveSeries.init(rawValue:)) ?? .f1
        liveStore.onSnapshot = { [weak self] snapshot in
            self?.handle(snapshot)
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

        if meetings.isEmpty, let cached = try? await cache.load(server: serverURL, season: season) {
            meetings = cached.envelope.data.sorted { $0.startDate < $1.startDate }
            loadState = .loaded(cached.savedAt)
        }

        loadState = .loading
        do {
            let envelope = try await APIClient(baseURL: serverURL).calendar(season: season, token: currentToken)
            meetings = envelope.data.sorted { $0.startDate < $1.startDate }
            loadState = .loaded(Date())
            try? await cache.save(server: serverURL, season: season, envelope: envelope)
        } catch {
            if meetings.isEmpty {
                loadState = .failed(Self.message(for: error))
            } else {
                loadState = .loaded(Date())
            }
        }
    }

    // MARK: Live

    func startLive() {
        guard let serverURL else { return }
        liveStarted = true
        liveConnecting = true
        liveStore.start(serverURL: serverURL, token: currentToken, series: series)
    }

    func stopLive() {
        liveStarted = false
        liveConnecting = false
        liveStore.stop()
        activity.update(snapshot: .disconnected())
    }

    func autoStartLiveOnce() {
        guard !autoStartAttempted else { return }
        autoStartAttempted = true
        startLive()
    }

    func toggleLive() {
        if liveStarted {
            stopLive()
        } else {
            startLive()
        }
    }

    private func handle(_ snapshot: LiveSnapshot) {
        liveSnapshot = snapshot
        liveConnecting = snapshot.statusReason == "connecting"
        if snapshot.sourceStatus != .disconnected {
            liveConnecting = false
        }
        activity.update(snapshot: snapshot)
    }

    func endLiveActivity() {
        activity.end()
    }

    // MARK: Settings

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
            let response = try await APIClient(baseURL: serverURL).health(token: currentToken)
            healthText = "\(response.status) · 数据库 \(response.database ? "正常" : "离线") · v\(response.version)"
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
