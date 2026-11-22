import Foundation
import SwiftUI
import UIKit
import SharedData

struct LiveNotice: Equatable {
    let id = UUID()
    let series: LiveSeries
    let text: String
}

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

    @Published var series: LiveSeries
    @Published var preferredLiveSeries: LiveSeries {
        didSet {
            guard oldValue != preferredLiveSeries else { return }
            defaults.set(preferredLiveSeries.rawValue, forKey: PreferenceKeys.liveSeries)
            manuallySelectedLiveSeries = nil
            refreshLiveSelection()
            updateActivity()
        }
    }
    var manuallySelectedLiveSeries: LiveSeries?
    @Published var liveSnapshots: [LiveSeries: LiveSnapshot] = [:]
    @Published var liveEntries: [LiveSeries: LiveSnapshot] = [:]
    @Published var scheduledLiveSession: NextSession?
    var currentSeasonLiveMeetings: [Meeting] = []
    var lastFinishedF1: LiveSnapshot?
    var displayedLiveSessionKey: String?
    @Published var driverRoster: [DriverStanding] = []
    @Published var rosterLoadError: String?
    @Published var settingsPresented = false
    @Published var liveNotice: LiveNotice?
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
    func setIslandBattle(_ numbers: [String]) {
        islandBattleNumbers = numbers
        islandMode = .battle
    }
    func resetIslandBattle() { islandBattleNumbers = []; updateActivity() }
    let liveStores: [LiveSeries: LiveStore] = [.f1: LiveStore(), .wec: LiveStore()]
    var historiesBySeries: [LiveSeries: [String: [LiveTelemetry]]] = [:]
    var recentLiveLaps: [LiveSeries: [String: [LiveCompletedLap]]] = [:]
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
    @Published var recentRaceSources: [FavoriteRaceSource] = []
    var recentRaceSavedAt: Date = .distantPast
    @Published var seasonArchive: APIEnvelope<[SeasonResultWeekend]>?
    @Published var seasonArchiveError: String?
    var seasonArchiveTask: Task<Void, Never>?
    @Published var credentialRevision = 0

    var dataContext: String { "\(serverURL?.absoluteString ?? serverText)|\(season)|\(credentialRevision)" }

    func invalidateCalendar() {
        calendarRequestID = UUID()
        seasonArchiveTask?.cancel()
        seasonArchiveTask = nil
        seasonArchive = nil
        seasonArchiveError = nil
        meetings = []
        loadState = .idle
        healthText = nil
        liveHistory = [:]
        driverRoster = []
        historiesBySeries = [:]
        recentLiveLaps = [:]
        liveSnapshots = [:]
        liveEntries = [:]
        scheduledLiveSession = nil
        currentSeasonLiveMeetings = []
        lastFinishedF1 = nil
        displayedLiveSessionKey = nil
        liveNotice = nil
        manuallySelectedLiveSeries = nil
        widgetHighlightsContext = nil
        rosterSavedAt = .distantPast
        recentRaceSources = []
        recentRaceSavedAt = .distantPast
        widgetPublisher.clear()
    }

    init() {
        let storedSeason = defaults.integer(forKey: PreferenceKeys.selectedSeason)
        let storedServer = defaults.string(forKey: PreferenceKeys.serverAddress)
        let preferredSeries = defaults.string(forKey: PreferenceKeys.liveSeries).flatMap(LiveSeries.init(rawValue:)) ?? .f1
        preferredLiveSeries = preferredSeries
        series = preferredSeries
        favoriteDriverID = defaults.string(forKey: PreferenceKeys.favoriteDriverId)
        islandMode = defaults.string(forKey: "mobileIslandMode").flatMap(IslandContentMode.init(rawValue:)) ?? .overview
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: .now)
        season = UIDevice.current.userInterfaceIdiom != .pad && storedSeason > 2000 ? storedSeason : currentYear
        serverText = storedServer?.isEmpty == false ? storedServer! : "http://localhost:38701"
        for (series, store) in liveStores {
            store.onSnapshot = { [weak self] snapshot in self?.handle(snapshot, from: series) }
            store.onConnectionState = { [weak self] snapshot in self?.handle(snapshot, from: series) }
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
