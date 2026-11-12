#if os(iOS) || os(macOS)
import SwiftUI
import Charts
import WidgetKit
import PitPulseShared

public struct RaceWeekendWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.kind, provider: RaceWeekendProvider()) { entry in
            NextRaceWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
                .widgetURL(WidgetDestination.calendar.url)
        }
        .configurationDisplayName("下一场 · Formula 1")
        .description("小尺寸看开赛倒计时，中尺寸查看赛事信息，大尺寸预览比赛周末。")
        .supportedFamilies(raceWidgetFamilies)
    }
}

private struct RaceCountdown: View {
    let start: Date
    let now: Date
    var large = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if start <= now {
                Text("开赛时间已到").font(.headline)
            } else if start.timeIntervalSince(now) >= 86400 {
                Text("\(Int(start.timeIntervalSince(now) / 86400))").font(.system(size: large ? 40 : 34, weight: .bold, design: .rounded)).monospacedDigit()
                Text("天后开赛").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(start, style: .timer).font(.system(size: large ? 32 : 23, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
        }.foregroundStyle(.primary)
    }
}

struct NextRaceWidgetView: View {
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
            #if os(iOS)
            case .accessoryInline:
                Text("\(race.session) · \(race.start.formatted(date: .omitted, time: .shortened)) · \(race.meeting)")
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "flag.checkered").font(.caption)
                    if race.start > entry.date {
                        Text("\(max(0, Int(race.start.timeIntervalSince(entry.date) / 86400)))天").font(.caption.bold())
                    } else { Text("更新").font(.caption2) }
                }.accessibilityLabel("下一场 \(race.session)")
            #endif
            default:
                VStack(alignment: .leading, spacing: 3) {
                    Text(race.meeting).font(.caption.bold()).lineLimit(1)
                    Text("\(race.session) · \(race.start.formatted(date: .abbreviated, time: .shortened))").font(.caption2)
                    Text(race.isStale(at: entry.date) ? "缓存过期" : "Formula 1").font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else { WidgetEmpty(title: "下一场比赛", icon: "flag.checkered") }
    }
    private func small(_ race: RaceWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            heading(race)
            Text(race.meeting).font(.system(size: 15, weight: .bold)).lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            RaceCountdown(start: race.start, now: entry.date)
            HStack { Text(race.session).foregroundStyle(widgetRed); Text(race.start, format: .dateTime.month(.twoDigits).day().hour().minute()) }
                .font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
    private func medium(_ race: RaceWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            heading(race)
            Spacer()
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(race.meeting).font(.headline).lineLimit(2)
                    Text("\(race.session) · \(race.start.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                    Text(race.location ?? "Formula 1").font(.system(size: 9)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    RaceCountdown(start: race.start, now: entry.date)
                    Text(race.start, format: .dateTime.month().day()).font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
    private func large(_ race: RaceWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(race)
            Text(race.meeting).font(.title2.bold()).lineLimit(2)
            HStack(alignment: .bottom) {
                RaceCountdown(start: race.start, now: entry.date, large: true)
                Spacer()
                Text(race.location ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Text(race.start, format: .dateTime.weekday(.wide).month().day()).font(.subheadline).foregroundStyle(.secondary)
            Divider()
            VStack(spacing: 12) {
                HStack {
                    Text("即将开始")
                        .font(.caption2.bold())
                    Spacer()
                    Text("当地显示时间")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array((race.sessions ?? []).filter { $0.start > entry.date }.prefix(5))) { session in
                    HStack {
                        Text(session.title)
                            .font(.caption.bold())
                        Spacer()
                        Text(session.start, format: .dateTime.month().day().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
    private func heading(_ race: RaceWidgetSnapshot) -> some View {
        WidgetHeading(label: "F1", trailing: race.isStale(at: entry.date) ? "缓存过期" : race.round.map { "F1 · R\($0)" }, warning: race.isStale(at: entry.date))
    }
}

#if DEBUG
#Preview("Widget Preview · Naxt Race") {
    WidgetSizePreview(families: [.systemSmall, .systemMedium, .systemLarge]) { family in
        NextRaceWidgetView(entry: RaceWeekendEntry(date: WidgetPreviewData.now, snapshot: WidgetPreviewData.weekend, timing: nil), previewFamily: family)
    }
}
#endif
#endif
