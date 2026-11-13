import AppKit
import SwiftUI
import SharedData

extension MeetingDetailView {
    var weekend: some View {
        VStack(spacing: PitPulseTheme.cardSpacing) {
            ForEach(sessionDays, id: \.day) { group in
                GlassCard(padding: 13) {
                    VStack(alignment: .leading, spacing: 8) {
                        CardHeader(title: group.day.formatted(.dateTime.weekday(.wide).month().day()))
                        ForEach(Array(group.sessions.enumerated()), id: \.element.id) { index, session in
                            let state = sessionState(session)
                            Button { resultSession = session } label: {
                            VStack(spacing: 0) {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(state == .running ? PitPulseTheme.accent : Color.primary.opacity(0.12))
                                        .frame(width: 3, height: 26)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.sessionType.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                        if let leader = meetingResults[session.id]?.first {
                                            Text("P1 \(leader.driverName) · \(leader.q3 ?? leader.q2 ?? leader.q1 ?? leader.bestLap ?? leader.raceTime ?? leader.time ?? leader.gap ?? "—")")
                                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                        }
                                        Text(sessionTimeRange(session))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 6)
                                    Text(state == .finished ? "查看成绩 ›" : sessionStateLabel(state))
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(state == .running ? PitPulseTheme.accent : Color.secondary)
                                }
                                .padding(.vertical, 7)
                                if index != group.sessions.count - 1 {
                                    Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                                }
                            }.contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(state != .finished)
                                .accessibilityIdentifier("calendar.session.\(session.id)")
                        }
                    }
                }
            }
            if sortedSessions.isEmpty {
                EmptyStateCard(symbol: "calendar.badge.clock", title: "周末赛程未提供", message: "服务器返回的分站数据中没有 Session。")
            }
        }
    }

    var sessionDays: [(day: Date, sessions: [Session])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sortedSessions) { calendar.startOfDay(for: $0.startTime) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!.sorted { $0.startTime < $1.startTime }) }
    }

    func sessionTimeRange(_ session: Session) -> String {
        let start = session.startTime.formatted(.dateTime.hour().minute())
        guard let end = session.endTime else { return start }
        return "\(start) – \(end.formatted(.dateTime.hour().minute()))"
    }

    // MARK: Weather
}
