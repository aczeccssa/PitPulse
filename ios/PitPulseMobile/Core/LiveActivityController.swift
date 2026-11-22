import ActivityKit
import Foundation
import SharedData

/// ActivityKit's `Activity` is a non-Sendable class whose update methods are
/// safe to call off the main actor. Box it so the async update task can capture
/// it without tripping Swift 6's region-based isolation checks.
private final class ActivityBox: @unchecked Sendable {
    let activity: Activity<PitPulseActivityAttributes>

    init(_ activity: Activity<PitPulseActivityAttributes>) {
        self.activity = activity
    }
}

/// Owns the Live Activity / Dynamic Island session. Updates are throttled to
/// meaningful state changes because SSE can deliver several frames per second.
@MainActor
final class LiveActivityController {
    private var box: ActivityBox?
    private var lastState: PitPulseActivityAttributes.ContentState?
    private var lastSampleDate: Date?
    private var lastUpdate: Task<Void, Never>?
    private var positionFocus = IslandPositionFocus()
    private var positionSession: String?
    private var positionHistory: [String: Int] = [:]
    private var positionArrows: [String: (delta: Int, at: TimeInterval)] = [:]

    init() {
        if let existing = Activity<PitPulseActivityAttributes>.activities.first {
            box = ActivityBox(existing)
            lastState = existing.content.state
            lastSampleDate = existing.content.staleDate?.addingTimeInterval(-90)
        }
    }

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var activeSeries: LiveSeries? {
        guard let activity = box?.activity, activity.activityState == .active || activity.activityState == .stale else { return nil }
        return activity.attributes.seriesTitle == "FIA WEC" ? .wec : .f1
    }

    var activeFavoriteName: String? { lastState?.favoriteName }

    func waitForLastUpdate() async { await lastUpdate?.value }

    func update(snapshot: LiveSnapshot, mode: IslandContentMode = .overview, favorite: LiveDriver? = nil,
                favoriteName: String? = nil, selectedNumbers: [String] = [], season: Int = 2026, existingOnly: Bool = false) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PITPULSE_DEMO_ACTIVITY"] == "1" { return }
        #endif
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if box != nil && activeSeries == nil {
            box = nil
            lastState = nil
            lastSampleDate = nil
        }

        guard let sessionID = snapshot.sessionId else { return }
        let expectedSeries = snapshot.isWec ? "FIA WEC" : "Formula 1"
        let matchesActivity = box.map {
            $0.activity.attributes.seriesTitle == expectedSeries
                && ($0.activity.attributes.sessionID == nil || $0.activity.attributes.sessionID == sessionID)
        } ?? false
        if existingOnly && !matchesActivity { return }
        if LiveIslandLogic.isFinished(snapshot.sessionStatus) {
            if matchesActivity { end() }
            return
        }

        guard snapshot.sourceStatus == .connected, !snapshot.drivers.isEmpty,
              LiveIslandLogic.isActive(snapshot.sessionStatus),
              let sampleDate = snapshot.updatedAt.flatMap(RFC3339.parse),
              LiveFreshness.isFresh(snapshot.updatedAt, maximumAge: 90) else { return }

        if box != nil && !matchesActivity { end() }
        if let lastSampleDate, sampleDate < lastSampleDate { return }
        let sessionKey = expectedSeries + String(describing: snapshot.sessionId)
        if positionSession != sessionKey {
            positionFocus = IslandPositionFocus(); positionHistory = [:]; positionArrows = [:]; positionSession = sessionKey
        }
        let now = ProcessInfo.processInfo.systemUptime
        let positions = Dictionary(snapshot.drivers.compactMap { driver in driver.position.map { (driver.number, $0) } }, uniquingKeysWith: { _, last in last })
        for (id, position) in positions {
            if let prior = positionHistory[id], prior != position { positionArrows[id] = (prior - position, now) }
        }
        positionHistory = positions
        positionArrows = positionArrows.filter { now - $0.value.at < 10 && positions[$0.key] != nil }
        positionFocus.update(positions: positions, now: now)
        let state = Self.contentState(snapshot: snapshot, mode: mode, favorite: favorite, favoriteName: favoriteName, selectedNumbers: selectedNumbers, focusedNumber: positionFocus.driverID, positionChanges: positionArrows.mapValues(\.delta), season: season)

        let refreshDeadline = lastSampleDate.map { sampleDate.timeIntervalSince($0) >= 30 } ?? true
        guard state != lastState || refreshDeadline else { return }

        let content = ActivityContent(state: state, staleDate: sampleDate.addingTimeInterval(90))
        if let box {
            lastState = state
            lastSampleDate = sampleDate
            lastUpdate?.cancel()
            lastUpdate = Task {
                guard !Task.isCancelled else { return }
                await box.activity.update(content)
            }
        } else if !existingOnly {
            let attributes = PitPulseActivityAttributes(seriesTitle: expectedSeries, sessionID: sessionID)
            if let created = try? Activity.request(attributes: attributes, content: content, pushType: nil) {
                box = ActivityBox(created)
                lastState = state
                lastSampleDate = sampleDate
            }
        }
    }

    /// One projection for the system activity and the preview; opening a preview never starts an activity.
    static func contentState(snapshot: LiveSnapshot, mode: IslandContentMode, favorite: LiveDriver? = nil, favoriteName: String? = nil, selectedNumbers: [String] = [], focusedNumber: String? = nil, positionChanges: [String: Int] = [:], season: Int = 2026) -> PitPulseActivityAttributes.ContentState {
        let leader = snapshot.drivers.first { $0.position == 1 }
        let challenger = snapshot.drivers.first { $0.position == 2 }
        let battle = IslandBattleSelection.drivers(in: snapshot.drivers, selected: selectedNumbers, favorite: favorite)
        func detail(_ driver: LiveDriver) -> PitPulseActivityAttributes.Driver {
            let speed = driver.telemetry.flatMap { LiveFreshness.isFresh($0.utc) ? $0.speed : nil }
            return .init(name: driver.name ?? driver.number, position: driver.position ?? driver.classPosition,
                asset: snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: driver.name ?? "", season: season),
                gap: driver.gap, interval: driver.interval,
                speed: speed.flatMap { $0.isFinite && $0 >= 0 && $0 < 1000 ? Int($0.rounded()) : nil },
                tire: driver.tireLabel, lastLap: driver.lastLap,
                sectors: Array((driver.sectors ?? []).prefix(3)).map { .init(time: $0.value, segments: Array(($0.segments ?? []).prefix(20)), personalFastest: $0.personalFastest, overallFastest: $0.overallFastest) })
        }
        let sorted = snapshot.drivers.filter { ($0.position ?? 0) > 0 }.sorted { $0.position! < $1.position! }
        let focusIndex = sorted.firstIndex { $0.number == focusedNumber } ?? 0
        let windowStart = min(max(0, sorted.count - 4), max(0, focusIndex - 2))
        let window = sorted.dropFirst(max(0, windowStart - 1)).prefix(7)
        return PitPulseActivityAttributes.ContentState(
            sessionName: snapshot.sessionName ?? snapshot.sessionType ?? "Live",
            meetingName: snapshot.meetingName ?? snapshot.circuitName ?? "PitPulse",
            statusLabel: snapshot.sourceMode == .live ? snapshot.englishSessionState : snapshot.englishStatus,
            lapLabel: snapshot.prefersSessionClock ? (snapshot.sessionClockLabel() ?? "—") : snapshot.englishLap,
            leaderName: leader?.name,
            leaderGap: leader?.gap,
            challengerName: challenger?.name,
            challengerGap: challenger?.gap,
            leaderAsset: leader.flatMap { snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: $0.name ?? "", season: season) },
            challengerAsset: challenger.flatMap { snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: $0.name ?? "", season: season) },
            trackLabel: snapshot.trackCondition.englishLabel,
            driverCount: snapshot.drivers.count,
            isStale: snapshot.sourceStatus == .stale,
            updatedLabel: snapshot.englishLastUpdated,
            presentation: mode.rawValue,
            favoriteName: favorite?.name ?? favoriteName,
            favoritePosition: favorite?.position ?? favorite?.classPosition,
            favoriteGap: favorite?.gap ?? favorite?.interval,
            favoriteGapLabel: favorite?.gap != nil ? "To leader" : (favorite?.interval != nil ? "To car ahead" : nil),
            favoriteAsset: favorite.flatMap { snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: $0.name ?? "", season: season) },
            podium: mode == .overview ? snapshot.drivers.filter { (1...3).contains($0.position ?? 0) }.sorted { $0.position! < $1.position! }.map { .init(name: $0.name ?? $0.number, position: $0.position, asset: snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: $0.name ?? "", season: season), gap: $0.gap) } : nil,
            battleDrivers: mode == .battle ? battle.map(detail) : nil, trackedDriver: mode == .favorite ? favorite.map(detail) : nil,
            battleGap: IslandBattleSelection.gap(between: battle),
            weather: mode == .overview || mode == .positionChanges ? nil : snapshot.weather.flatMap { weather in
                // Weather updates are less frequent than car telemetry. Do not
                // carry an old weather report into a fresh activity indefinitely.
                guard LiveFreshness.isFresh(weather.utc, maximumAge: 300) else { return nil }
                return .init(rainfall: weather.rainfall,
                    airTemperature: weather.airTemp.flatMap { $0.isFinite ? $0 : nil },
                    trackTemperature: weather.trackTemp.flatMap { $0.isFinite ? $0 : nil })
            },
            positionDrivers: mode == .positionChanges ? window.map { .init(name: $0.name ?? $0.number, position: $0.position, asset: snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: $0.name ?? "", season: season), gap: $0.gap, positionChange: positionChanges[$0.number]) } : nil,
            positionFocus: mode == .positionChanges && sorted.indices.contains(focusIndex) ? (sorted[focusIndex].name ?? sorted[focusIndex].number) : nil,
            positionWindowStart: mode == .positionChanges ? windowStart : nil,
            countryCode: snapshot.countryCode
        )

    }

    #if DEBUG
    /// QA-only: start a representative activity so the Dynamic Island and the
    /// lock-screen presentation can be inspected in the simulator without a
    /// session currently on track. Never compiled into Release.
    func demoStart() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        var state = PitPulseActivityAttributes.ContentState(
            sessionName: "Race",
            meetingName: "São Paulo Grand Prix",
            statusLabel: "Demo",
            lapLabel: "L32/71",
            leaderName: "Lando NORRIS",
            leaderGap: "LEADER",
            challengerName: "Max VERSTAPPEN",
            challengerGap: "+2.418",
            leaderAsset: "helmet-norris-2026",
            challengerAsset: "helmet-max_verstappen-2026",
            trackLabel: "Green flag · Track clear",
            driverCount: 22,
            isStale: false,
            updatedLabel: "Just now"
        )
        let sectors: [PitPulseActivityAttributes.Sector] = [
            .init(time: "23.658", segments: [2049, 2051, 2049, 2048, 2049, 2051], personalFastest: true),
            .init(time: "32.421", segments: [2049, 2048, 2049, 2049, 2048, 2049]),
            .init(time: nil, segments: [2049, 2049, nil, nil, nil, nil])]
        let leader = PitPulseActivityAttributes.Driver(name: "Lando NORRIS", position: 1, asset: "helmet-norris-2026", gap: "LEADER", tire: "S 18", sectors: sectors)
        let tracked = PitPulseActivityAttributes.Driver(name: "Max VERSTAPPEN", position: 2, asset: "helmet-max_verstappen-2026", gap: "+2.418", interval: "+0.842", tire: "M 12", lastLap: "1:12.345", sectors: sectors, positionChange: 1)
        let third = PitPulseActivityAttributes.Driver(name: "Charles LECLERC", position: 3, asset: "helmet-leclerc-2026", gap: "+4.216", positionChange: -1)
        state.presentation = ProcessInfo.processInfo.environment["PITPULSE_DEMO_MODE"] ?? "overview"
        state.countryCode = "BR"
        state.podium = [leader, tracked, third]
        state.battleDrivers = [leader, tracked]; state.battleGap = "+2.418"
        state.trackedDriver = tracked
        state.positionDrivers = [leader, tracked, third,
            .init(name: "Oscar PIASTRI", position: 4, gap: "+6.104"),
            .init(name: "George RUSSELL", position: 5, gap: "+8.572")]
        state.positionFocus = tracked.name; state.positionWindowStart = 0
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(600))
        let attributes = PitPulseActivityAttributes(seriesTitle: "Formula 1")
        if let created = try? Activity.request(attributes: attributes, content: content, pushType: nil) {
            box = ActivityBox(created)
            lastState = state
        }
    }
    #endif

    func end() {
        lastUpdate?.cancel()
        lastUpdate = nil
        lastState = nil
        lastSampleDate = nil
        positionFocus = IslandPositionFocus(); positionSession = nil; positionHistory = [:]; positionArrows = [:]
        guard let box else { return }
        self.box = nil
        lastUpdate = Task { await box.activity.end(nil, dismissalPolicy: .immediate) }
    }
}
