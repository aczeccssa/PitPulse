#if os(iOS) || os(macOS)
import SwiftUI
import Charts
import WidgetKit
import SharedData

public struct WeekendScheduleWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.scheduleKind, provider: RaceWeekendProvider()) { entry in
            WeekendScheduleWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
                .widgetURL(WidgetDestination.calendar.url)
        }
        .configurationDisplayName("比赛周末 · Formula 1")
        .description("小尺寸聚焦最近两场，中尺寸按场次展开，大尺寸显示完整场次安排。")
        .supportedFamilies(scheduleWidgetFamilies)
    }
}

struct WeekendScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: RaceWeekendEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }

    var body: some View {
        if let race = entry.snapshot {
            switch family {
            case .systemSmall: small(race)
            case .systemMedium: medium(race)
            case .systemLarge: large(race)
            default:
                VStack(alignment: .leading, spacing: 3) {
                    Text(race.meeting).font(.caption.bold()).lineLimit(1)
                    ForEach(Array(upcoming(race).prefix(2))) { row in
                        HStack { Text(row.title); Spacer(); Text(row.start, style: .time) }.font(.caption2)
                    }
                }
            }
        } else { WidgetEmpty(title: "比赛周末", icon: "calendar") }
    }

    private func weekendSessions(_ race: RaceWidgetSnapshot) -> [RaceWidgetSession] {
        let rows = (race.sessions ?? []).sorted { $0.start < $1.start }
        return rows.isEmpty ? [RaceWidgetSession(id: race.session, title: race.session, start: race.start)] : rows
    }

    private func upcoming(_ race: RaceWidgetSnapshot) -> [RaceWidgetSession] {
        (race.sessions ?? []).filter { $0.start > entry.date }
    }

    private func small(_ race: RaceWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            WidgetHeading(label: "WEEKEND")
            Text(race.meeting).font(.system(size: 14, weight: .bold)).lineLimit(2)
            Spacer(minLength: 0)
            ForEach(Array(upcoming(race).prefix(2))) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title).font(.caption.bold()).foregroundStyle(row.title == race.session ? widgetRed : .primary)
                    Spacer(minLength: 3)
                    Text(row.start, style: .time).font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func medium(_ race: RaceWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeading(label: "WEEKEND")
            Text(race.meeting).font(.headline).lineLimit(1)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array((race.sessions ?? []).prefix(5))) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(row.start == race.start ? .red : Color.primary.opacity(0.16)).frame(height: 3).padding(.trailing, 5)
                        Text(row.title).font(.system(size: 10, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(row.start, format: .dateTime.month(.twoDigits).day()).font(.system(size: 8)).foregroundStyle(.secondary)
                        Text(row.start, style: .time).font(.system(size: 10, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func large(_ race: RaceWidgetSnapshot) -> some View {
        let sessions = Array(weekendSessions(race).prefix(5))
        let days = Array(Set(sessions.map { Calendar.current.startOfDay(for: $0.start) })).sorted().prefix(3)
        let stale = race.isStale(at: entry.date)
        return VStack(alignment: .leading, spacing: 8) {
            WidgetHeading(label: "FULL WEEKEND",
                          trailing: stale ? "缓存过期" : race.round.map { "F1 · R\($0)" },
                          warning: stale)
            Text(race.meeting)
                .font(.system(size: 22, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ForEach(Array(days), id: \.self) { day in
                    let isRaceDay = sessions.contains {
                        WeekendSessionStyle.isRace($0.title) && Calendar.current.isDate($0.start, inSameDayAs: day)
                    }
                    Text(WeekendSessionStyle.dayLabel(day))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isRaceDay ? widgetRed : .secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isRaceDay ? widgetRed.opacity(0.12) : Color.primary.opacity(0.06), in: Capsule())
                }
                Spacer(minLength: 0)
                Text(WeekendSessionStyle.range(sessions))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 2)
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, row in
                    sessionRow(row, current: race.session)
                    if index < sessions.count - 1 { Divider().padding(.leading, 68) }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text(race.location ?? "Formula 1")
                Spacer()
                Text("本地时间")
            }.font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }

    private func sessionRow(_ row: RaceWidgetSession, current: String) -> some View {
        let isRace = WeekendSessionStyle.isRace(row.title)
        let isCurrent = row.title == current
        return HStack(spacing: 10) {
            Text(WeekendSessionStyle.category(row.title))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isRace ? widgetRed : .secondary)
                .frame(width: 56, alignment: .leading).lineLimit(1).minimumScaleFactor(0.75)
            Text(row.title).font(.system(size: 13, weight: isRace ? .bold : .semibold)).lineLimit(1)
            if isCurrent && !isRace {
                Circle().fill(widgetRed).frame(width: 5, height: 5)
            }
            Spacer(minLength: 4)
            Text(WeekendSessionStyle.clock(row.start))
                .font(.system(size: 14, weight: isRace ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(isRace ? widgetRed : .primary)
            Text(WeekendSessionStyle.monthDay(row.start))
                .font(.system(size: 8)).foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .background(isRace ? widgetRed.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .leading) {
            if isRace {
                RoundedRectangle(cornerRadius: 1.5).fill(widgetRed)
                    .frame(width: 3, height: 30).padding(.leading, -1)
            }
        }
    }
}

#if DEBUG
#Preview("Widget Preview · Weekend Schedule") {
    WidgetSizePreview(families: [.systemSmall, .systemMedium, .systemLarge]) { family in
        WeekendScheduleWidgetView(entry: RaceWeekendEntry(date: WidgetPreviewData.now, snapshot: WidgetPreviewData.weekend, timing: nil), previewFamily: family)
    }
}
#endif
#endif
