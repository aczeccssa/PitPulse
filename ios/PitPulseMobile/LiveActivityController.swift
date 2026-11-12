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
    private var positionFocus = IslandPositionFocus()
    private var positionSession: String?
    private var positionHistory: [String: Int] = [:]
    private var positionArrows: [String: (delta: Int, at: TimeInterval)] = [:]

    init() {
        if let existing = Activity<PitPulseActivityAttributes>.activities.first {
            box = ActivityBox(existing)
            lastState = existing.content.state
        }
    }

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func update(snapshot: LiveSnapshot, mode: IslandContentMode = .overview, favorite: LiveDriver? = nil, favoriteName: String? = nil, selectedNumbers: [String] = []) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // A reconnect resets the store to a transient "connecting" snapshot;
        // keep the existing activity alive through it.
        if snapshot.sourceStatus == .disconnected, snapshot.statusReason == "connecting" {
            return
        }

        if snapshot.sourceStatus == .disconnected
            || snapshot.sessionId == nil
            || LiveIslandLogic.isFinished(snapshot.sessionStatus) {
            end()
            return
        }

        let expectedSeries = snapshot.isWec ? "FIA WEC" : "Formula 1"
        if let box, box.activity.attributes.seriesTitle != expectedSeries { end() }
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
        let state = Self.contentState(snapshot: snapshot, mode: mode, favorite: favorite, favoriteName: favoriteName, selectedNumbers: selectedNumbers, focusedNumber: positionFocus.driverID, positionChanges: positionArrows.mapValues(\.delta))

        guard state != lastState else { return }

        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(90))
        if let box {
            lastState = state
            Task { await box.activity.update(content) }
        } else {
            let attributes = PitPulseActivityAttributes(
                seriesTitle: snapshot.isWec ? "FIA WEC" : "Formula 1"
            )
            if let created = try? Activity.request(attributes: attributes, content: content, pushType: nil) {
                box = ActivityBox(created)
                lastState = state
            }
        }
    }

    /// One projection for the system activity and the preview; opening a preview never starts an activity.
    static func contentState(snapshot: LiveSnapshot, mode: IslandContentMode, favorite: LiveDriver? = nil, favoriteName: String? = nil, selectedNumbers: [String] = [], focusedNumber: String? = nil, positionChanges: [String: Int] = [:]) -> PitPulseActivityAttributes.ContentState {
        let leader = snapshot.drivers.first { $0.position == 1 }
        let challenger = snapshot.drivers.first { $0.position == 2 }
        let battle = IslandBattleSelection.drivers(in: snapshot.drivers, selected: selectedNumbers, favorite: favorite)
        func detail(_ driver: LiveDriver) -> PitPulseActivityAttributes.Driver {
            let speed = driver.telemetry.flatMap { LiveFreshness.isFresh($0.utc) ? $0.speed : nil }
            return .init(name: driver.name ?? driver.number, position: driver.position ?? driver.classPosition,
                asset: snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: driver.name ?? "", season: 2026),
                gap: driver.gap, interval: driver.interval,
                speed: speed.flatMap { $0.isFinite && $0 >= 0 && $0 < 1000 ? Int($0.rounded()) : nil },
                tire: driver.tireLabel, lastLap: driver.lastLap,
                sectors: Array((driver.sectors ?? []).prefix(3)).map { .init(time: $0.value, segments: Array(($0.segments ?? []).prefix(20)), personalFastest: $0.personalFastest, overallFastest: $0.overallFastest) })
        }
        let sorted = snapshot.drivers.filter { ($0.position ?? 0) > 0 }.sorted { $0.position! < $1.position! }
        let focusIndex = sorted.firstIndex { $0.number == focusedNumber } ?? 0
        let windowStart = min(max(0, sorted.count - 5), max(0, focusIndex - 2))
        let window = sorted.dropFirst(max(0, windowStart - 1)).prefix(7)
        return PitPulseActivityAttributes.ContentState(
            sessionName: snapshot.sessionName ?? snapshot.sessionType ?? "Live",
            meetingName: snapshot.meetingName ?? snapshot.circuitName ?? "PitPulse",
            statusLabel: snapshot.sourceMode == .live ? snapshot.sessionStateLabel : snapshot.statusLabel,
            lapLabel: snapshot.lapLabel,
            leaderName: leader?.name,
            leaderGap: leader?.gap,
            challengerName: challenger?.name,
            challengerGap: challenger?.gap,
            leaderAsset: leader.flatMap { snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: $0.name ?? "", season: 2026) },
            challengerAsset: challenger.flatMap { snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: $0.name ?? "", season: 2026) },
            trackLabel: snapshot.trackCondition.label,
            driverCount: snapshot.drivers.count,
            isStale: snapshot.sourceStatus == .stale,
            updatedLabel: snapshot.lastUpdatedLabel,
            presentation: mode.rawValue,
            favoriteName: favorite?.name ?? favoriteName,
            favoritePosition: favorite?.position ?? favorite?.classPosition,
            favoriteGap: favorite?.gap ?? favorite?.interval,
            favoriteGapLabel: favorite?.gap != nil ? "距领先" : (favorite?.interval != nil ? "距前车" : nil),
            favoriteAsset: favorite.flatMap { snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: $0.name ?? "", season: 2026) },
            podium: mode == .overview ? snapshot.drivers.filter { (1...3).contains($0.position ?? 0) }.sorted { $0.position! < $1.position! }.map { .init(name: $0.name ?? $0.number, position: $0.position, asset: snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: $0.name ?? "", season: 2026), gap: $0.gap) } : nil,
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
            positionDrivers: mode == .positionChanges ? window.map { .init(name: $0.name ?? $0.number, position: $0.position, asset: snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: $0.name ?? "", season: 2026), gap: $0.gap, positionChange: positionChanges[$0.number]) } : nil,
            positionFocus: mode == .positionChanges && sorted.indices.contains(focusIndex) ? (sorted[focusIndex].name ?? sorted[focusIndex].number) : nil,
            positionWindowStart: mode == .positionChanges ? windowStart : nil
        )

    }

    #if DEBUG
    /// QA-only: start a representative activity so the Dynamic Island and the
    /// lock-screen presentation can be inspected in the simulator without a
    /// session currently on track. Never compiled into Release.
    func demoStart() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = PitPulseActivityAttributes.ContentState(
            sessionName: "Race",
            meetingName: "São Paulo Grand Prix",
            statusLabel: "演示 · 非实时",
            lapLabel: "L32/71",
            leaderName: "Lando NORRIS",
            leaderGap: "LEADER",
            challengerName: "Max VERSTAPPEN",
            challengerGap: "+2.418",
            leaderAsset: "helmet-norris-2026",
            challengerAsset: "helmet-max_verstappen-2026",
            trackLabel: "绿旗 · 赛道畅通",
            driverCount: 22,
            isStale: false,
            updatedLabel: "刚刚"
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(600))
        let attributes = PitPulseActivityAttributes(seriesTitle: "Formula 1")
        if let created = try? Activity.request(attributes: attributes, content: content, pushType: nil) {
            box = ActivityBox(created)
            lastState = state
        }
    }
    #endif

    func end() {
        lastState = nil
        positionFocus = IslandPositionFocus(); positionSession = nil; positionHistory = [:]; positionArrows = [:]
        guard let box else { return }
        self.box = nil
        Task { await box.activity.end(nil, dismissalPolicy: .immediate) }
    }
}
