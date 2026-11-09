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

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func update(snapshot: LiveSnapshot) {
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

        let leader = snapshot.drivers.min { ($0.position ?? Int.max) < ($1.position ?? Int.max) }
        let state = PitPulseActivityAttributes.ContentState(
            sessionName: snapshot.sessionName ?? snapshot.sessionType ?? "Live",
            meetingName: snapshot.meetingName ?? snapshot.circuitName ?? "PitPulse",
            statusLabel: snapshot.sessionStateLabel,
            lapLabel: snapshot.lapLabel,
            leaderName: leader?.name,
            leaderGap: leader?.gap,
            trackLabel: snapshot.trackCondition.label,
            driverCount: snapshot.drivers.count,
            isStale: snapshot.sourceStatus == .stale,
            updatedLabel: snapshot.lastUpdatedLabel
        )

        guard state != lastState else { return }
        lastState = state

        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(90))
        if let box {
            Task { await box.activity.update(content) }
        } else {
            let attributes = PitPulseActivityAttributes(
                seriesTitle: snapshot.isWec ? "FIA WEC" : "Formula 1"
            )
            if let created = try? Activity.request(attributes: attributes, content: content, pushType: nil) {
                box = ActivityBox(created)
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
            statusLabel: "进行中",
            lapLabel: "L32/71",
            leaderName: "Lando NORRIS",
            leaderGap: "LEADER",
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
