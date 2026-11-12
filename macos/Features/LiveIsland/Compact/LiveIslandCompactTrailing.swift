import AppKit
import SwiftUI
import SharedData

struct LiveIslandCompactTrailing: View {
    @ObservedObject var model: AppModel
    @ObservedObject var actions: LiveIslandActions

    private var favoriteID: String? {
        model.favoriteDriverId(for: actions.snapshot.isWec ? .wec : .f1)
    }

    private var favorite: LiveDriver? {
        LiveIslandLogic.matchedDriver(
            favoriteId: favoriteID,
            favorites: model.favoriteDrivers,
            drivers: actions.snapshot.sourceStatus == .connected ? actions.snapshot.drivers : []
        )
    }

    private var hasTiming: Bool { actions.snapshot.sourceStatus == .connected }

    private var statusText: String {
        if actions.snapshot.statusReason == "scheduled_session_waiting_for_live" {
            return "赛历安排；等待实时数据"
        }
        return actions.snapshot.statusLabel
    }

    var body: some View {
        Button { actions.expand?() } label: {
            HStack(spacing: 7) {
                if hasTiming {
                    if actions.snapshot.sourceMode == .replay {
                        Text("回放")
                            .font(.system(size: 9))
                    }
                    if let favorite {
                        LiveHelmetView(model: model, driver: favorite, size: 18, isWec: actions.snapshot.isWec)
                        Text("\(actions.snapshot.isWec ? "#\(favorite.number)" : MotorsportAsset.abbreviation(favorite.name ?? favorite.number)) P\(favorite.position.map(String.init) ?? "—")")
                            .monospacedDigit()
                    } else if favoriteID == nil {
                        Image(systemName: "star")
                            .help("选择关注车手")
                    } else {
                        Text("No selected")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .help("关注的车手不在本次会话中")
                            .accessibilityLabel("未选择，关注的车手不在本次会话中")
                    }
                } else {
                    if actions.snapshot.sourceMode == .replay {
                        Text("回放").font(.system(size: 9)).foregroundStyle(.orange)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if actions.snapshot.sessionId == nil, actions.snapshot.sessionName == nil,
                           let next = CalendarLogic.nextSession(in: model.meetings, now: context.date) {
                            Text(CalendarLogic.countdownText(until: next.session.startTime, now: context.date))
                                .monospacedDigit()
                        } else {
                            LiveWaitingIndicator(detail: statusText)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("展开 Live Island，选择或切换关注车手")
        .foregroundStyle(Color.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasTiming
            ? "\(actions.snapshot.statusLabel)，第 \((favorite?.lapCount ?? actions.snapshot.lapCount).map(String.init) ?? "—") 圈，关注车手 \(favorite?.name ?? "未选择")，名次 P\(favorite?.position.map(String.init) ?? "—")"
            : statusText)
        .environment(\.colorScheme, .dark)
    }
}

