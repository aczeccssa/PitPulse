import ActivityKit
import Foundation
import PitPulseData
import PitPulseShared

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

    init() {
        if let existing = Activity<PitPulseActivityAttributes>.activities.first {
            box = ActivityBox(existing)
            lastState = existing.content.state
        }
    }

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func update(snapshot: LiveSnapshot, mode: IslandContentMode = .overview, favorite: LiveDriver? = nil, favoriteName: String? = nil) {
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
        let leader = snapshot.drivers.first { $0.position == 1 }
        let challenger = snapshot.drivers.first { $0.position == 2 }
        let state = PitPulseActivityAttributes.ContentState(
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
            favoriteAsset: favorite.flatMap { snapshot.isWec ? nil : MotorsportAssetName.helmetName(name: $0.name ?? "", season: 2026) }
        )

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
        guard let box else { return }
        self.box = nil
        Task { await box.activity.end(nil, dismissalPolicy: .immediate) }
    }
}
