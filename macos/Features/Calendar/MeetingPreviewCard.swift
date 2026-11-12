import AppKit
import SwiftUI
import SharedData

struct MeetingPreviewCard: View {
    let meeting: Meeting
    let openDetail: () -> Void

    var nextSession: NextSession? {
        CalendarLogic.nextSession(in: [meeting], now: Date())
    }

    var body: some View {
        GlassCard(padding: 15) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(CountryFlag.display(country: meeting.country, code: meeting.countryCode))
                        .font(.system(size: 30))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("第 \(meeting.round.map(String.init) ?? "—") 站")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(PitPulseTheme.accent)
                        Text(String(meeting.season))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text(meeting.location)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)

                VStack(alignment: .leading, spacing: 7) {
                    fact(icon: "calendar", value: "\(meeting.startDate.formatted(.dateTime.month().day())) – \(meeting.endDate.formatted(.dateTime.month().day()))")
                    if let circuit = meeting.circuit {
                        fact(icon: "mappin.and.ellipse", value: circuit.name ?? meeting.location)
                    }
                    fact(icon: "list.number", value: "\(meeting.sessions.count) 节 Session")
                }

                if let nextSession {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("下一节")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(PitPulseTheme.accent)
                        Text(nextSession.session.sessionType.displayName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(nextSession.session.startTime.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PitPulseTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Spacer(minLength: 6)

                Button(action: openDetail) {
                    HStack(spacing: 5) {
                        Text("打开比赛详情")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("查看该分站的周末、天气与分析")
            }
        }
    }

    func fact(icon: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}
