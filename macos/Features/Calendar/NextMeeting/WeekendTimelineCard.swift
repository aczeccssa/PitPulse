import AppKit
import SwiftUI
import SharedData

struct WeekendTimelineCard: View {
    let meeting: Meeting
    let now: Date

    var sessions: [Session] {
        meeting.sessions.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "比赛周末")
                if sessions.isEmpty {
                    Text("暂无 Session 数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            SessionTimelineRow(
                                session: session,
                                state: state(for: session),
                                isLast: index == sessions.count - 1
                            )
                        }
                    }
                }
            }
        }
    }

    func state(for session: Session) -> SessionTimelineRow.State {
        if session.status == .cancelled { return .cancelled }
        if session.status == .postponed { return .postponed }
        let end = session.endTime ?? session.startTime.addingTimeInterval(7_200)
        if now >= end || session.status == .finished { return .finished }
        if now >= session.startTime { return .running }
        return .upcoming
    }
}

struct SessionTimelineRow: View {
    enum State {
        case finished, running, upcoming, cancelled, postponed
    }

    let session: Session
    let state: State
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(dotFill)
                    .frame(width: 8, height: 8)
                    .overlay {
                        if case .running = state {
                            Circle().strokeBorder(PitPulseTheme.accent.opacity(0.35), lineWidth: 4)
                        }
                    }
                    .padding(.top, 5)
                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)

            HStack(alignment: .center, spacing: 8) {
                Text(session.sessionType.displayName)
                    .font(.system(size: 13, weight: state.isUpcoming ? .semibold : .medium))
                    .foregroundStyle(state.isUpcoming ? Color.primary : Color.secondary)
                Spacer(minLength: 6)
                Text(session.startTime.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(state.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(state.tint)
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.bottom, isLast ? 2 : 9)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.sessionType.displayName)，\(session.startTime.formatted(date: .abbreviated, time: .shortened))，\(state.label)")
    }

    var dotFill: Color {
        switch state {
        case .finished: PitPulseTheme.accent
        case .running: PitPulseTheme.accent
        case .upcoming: Color.secondary.opacity(0.45)
        case .cancelled, .postponed: Color.orange
        }
    }
}

private extension SessionTimelineRow.State {
    var isUpcoming: Bool {
        if case .upcoming = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .finished: "已结束"
        case .running: "进行中"
        case .upcoming: "未开始"
        case .cancelled: "已取消"
        case .postponed: "延期"
        }
    }

    var tint: Color {
        switch self {
        case .finished: .secondary
        case .running: PitPulseTheme.accent
        case .upcoming: .secondary
        case .cancelled, .postponed: .orange
        }
    }
}

// MARK: - Conditions + circuit
