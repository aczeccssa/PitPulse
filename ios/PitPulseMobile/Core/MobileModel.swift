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

    @Published var meetings: [Meeting] = []
    @Published var loadState: LoadState = .idle
    @Published var liveSnapshot = LiveSnapshot.disconnected()
    @Published var liveConnecting = false
    @Published var healthText: String?
    @Published var liveHistory: [String: [LiveTelemetry]] = [:]

    @Published var season: Int {
        didSet { defaults.set(season, forKey: PreferenceKeys.selectedSeason); invalidateCalendar() }
    }

    @Published var serverText: String {
        didSet {
            defaults.set(serverText, forKey: PreferenceKeys.serverAddress)
            if oldValue != serverText { invalidateCalendar(); if liveStarted { startLive() } }
        }
    }

    @Published var series: LiveSeries = .f1
    @Published var liveSnapshots: [LiveSeries: LiveSnapshot] = [:]
    @Published var driverRoster: [DriverStanding] = []
    @Published var rosterLoadError: String?
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
    @Published var islandBattleNumbers: [String] = []
    func toggleIslandBattle(_ number: String) {
        islandBattleNumbers = IslandBattleSelection.toggled(number, in: islandBattleNumbers)
        islandMode = .battle
    }
    func resetIslandBattle() { islandBattleNumbers = []; updateActivity() }
    let liveStores: [LiveSeries: LiveStore] = [.f1: LiveStore(), .wec: LiveStore()]
    var historiesBySeries: [LiveSeries: [String: [LiveTelemetry]]] = [:]
    var liveConnectionContext: String?

    let defaults = UserDefaults.standard
    let keychain = KeychainStore(service: "com.pitpulse.mobile")
    let cache = DiskCalendarCache()
    let activity = LiveActivityController()
    var liveStarted = false
    var calendarRequestID = UUID()
    let widgetPublisher = WidgetSnapshotPublisher()
    var widgetHighlightsContext: String?
    var rosterSavedAt: Date = .distantPast
    var recentRaceSources: [FavoriteRaceSource] = []
    var recentRaceSavedAt: Date = .distantPast
    @Published var credentialRevision = 0

    var dataContext: String { "\(serverURL?.absoluteString ?? serverText)|\(season)|\(credentialRevision)" }

    func invalidateCalendar() {
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

}
