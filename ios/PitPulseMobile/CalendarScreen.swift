import SwiftUI
import PitPulseData
import PitPulseShared

struct CalendarScreen: View {
    @EnvironmentObject private var model: MobileModel

    var body: some View {
        NavigationStack {
            Group {
                if model.meetings.isEmpty {
                    ContentUnavailableView {
                        Label("暂无赛历", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text(model.loadState.errorText ?? "连接服务器后加载 \(model.season) 赛季赛历。")
                    } actions: {
                        Button("重新加载") { Task { await model.loadCalendar(force: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if let next = CalendarLogic.nextSession(in: model.meetings, now: Date()) {
                            Section { NextSessionCard(next: next) }
                        }
                        Section("赛历 \(String(model.season))") {
                            ForEach(model.meetings) { meeting in
                                MeetingRow(meeting: meeting)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("赛程")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.loadState.isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await model.loadCalendar(force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable { await model.loadCalendar(force: true) }
            .task { await model.loadCalendar() }
            .onChange(of: model.season) { _, _ in
                Task { await model.loadCalendar(force: true) }
            }
        }
    }
}

private struct NextSessionCard: View {
    let next: NextSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(CountryFlag.emoji(for: next.meeting.countryCode) ?? "🏁")
                    .font(.title3)
                Text(next.meeting.name)
                    .font(.headline)
                Spacer()
                if let round = next.meeting.round {
                    Text("第 \(round) 站")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(next.session.sessionType.displayName) · \(next.session.startTime.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("距开始 \(CalendarLogic.countdownText(until: next.session.startTime, now: context.date))")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CountryFlag.emoji(for: meeting.countryCode) ?? "🌐")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.name)
                        .font(.headline)
                    Text("\(meeting.startDate.formatted(date: .abbreviated, time: .omitted)) – \(meeting.endDate.formatted(date: .abbreviated, time: .omitted)) · \(meeting.location)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let round = meeting.round {
                    Text("R\(round)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(meeting.sessions) { session in
                        SessionChip(session: session)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SessionChip: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(session.sessionType.displayName)
                .font(.caption2.weight(.semibold))
            Text(session.startTime.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(chipColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(chipColor)
    }

    private var chipColor: Color {
        switch session.status {
        case .live: return .red
        case .finished: return .gray
        default: return .primary
        }
    }
}
