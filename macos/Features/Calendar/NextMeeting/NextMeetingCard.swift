import AppKit
import SwiftUI
import SharedData

struct NextMeetingCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let meeting = CalendarLogic.featuredMeeting(in: model.meetings, now: context.date) {
                    VStack(alignment: .leading, spacing: PitPulseTheme.cardSpacing) {
                        RaceHeroCard(
                            meeting: meeting,
                            nextSession: CalendarLogic.nextSession(in: [meeting], now: context.date),
                            now: context.date
                        )
                        WeekendTimelineCard(meeting: meeting, now: context.date)
                        WeekendConditionsCard(meeting: meeting, now: context.date)
                        SeasonLeaderCard()
                    }
                    .padding(.horizontal, PitPulseTheme.pagePadding)
                    .padding(.vertical, 14)
                    .background(CalendarScrollAppearance())
                } else if model.isRefreshing {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在读取赛历…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    EmptyStateCard(
                        symbol: AppSymbol.calendar.resolvedSystemName(),
                        title: "暂无比赛",
                        message: "该赛季还没有可用的赛程。切换年份或刷新后重试。"
                    )
                    .padding(PitPulseTheme.pagePadding)
                    .padding(.top, 24)
                }
            }
        }
    }
}

// MARK: - Hero

struct RaceHeroCard: View {
    let meeting: Meeting
    let nextSession: NextSession?
    let now: Date

    var body: some View {
        GlassCard(padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(CountryFlag.emoji(for: meeting.countryCode) ?? "🌐")
                        .font(.system(size: 22))
                        .accessibilityLabel("举办国 \(meeting.country)")

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("R\(meeting.round.map(String.init) ?? "—")")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(PitPulseTheme.accent)
                            Text(meeting.name)
                                .font(.system(size: 15.5, weight: .semibold))
                                .tracking(-0.1)
                                .lineLimit(1)
                        }
                        Text("\(meeting.circuit?.name ?? meeting.location) · \(meeting.startDate.formatted(.dateTime.month().day())) – \(meeting.endDate.formatted(.dateTime.month().day()))")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if let nextSession {
                        CountdownRow(next: nextSession, now: now)
                    }
                }

                if let nextSession {
                    HStack(spacing: 5) {
                        Circle().fill(PitPulseTheme.accent).frame(width: 4, height: 4)
                        Text("下一节 \(nextSession.session.sessionType.displayName)")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(nextSession.session.startTime.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if meeting.status != .scheduled {
                            Text(meeting.status.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal").font(.system(size: 11))
                        Text("本周末赛程已结束")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
}
