import SwiftUI
import PitPulseData
import PitPulseShared

struct MeetingDetailView: View {
    let meeting: Meeting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                MeetingMapView(meeting: meeting)
                sessions
            }
            .padding(16)
            .background(CalendarScrollAppearance())
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CountryFlag.display(country: meeting.country, code: meeting.countryCode))
                .font(.headline)
            Text(meeting.location)
                .foregroundStyle(.secondary)
            HStack {
                Label(meeting.status.displayName, systemImage: statusSymbol)
                Spacer()
                Text("第 \(meeting.round.map(String.init) ?? "—") 站")
            }
            .font(.caption)
        }
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("比赛周末")
                .font(.headline)
            if meeting.sessions.isEmpty {
                Text("暂无 Session 数据。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(meeting.sessions) { session in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.sessionType.displayName)
                                .font(.body.weight(.medium))
                            Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(session.status.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    if session.id != meeting.sessions.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var statusSymbol: String {
        switch meeting.status {
        case .scheduled: AppSymbol.calendar.resolvedSystemName()
        case .postponed: AppSymbol.warning.resolvedSystemName()
        case .cancelled: AppSymbol.warning.resolvedSystemName()
        }
    }
}
