#if os(iOS) || os(macOS)
import SwiftUI
import Charts
import WidgetKit
import SharedData

struct UpcomingWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: UpcomingWidgetSnapshot?
}

struct UpcomingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingWidgetEntry {
        UpcomingWidgetEntry(date: .now, snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (UpcomingWidgetEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var dates = [now]
        if let saved = current.snapshot?.savedAt {
            let expiry = saved.addingTimeInterval(6 * 3600 + 1)
            if expiry > now { dates.append(expiry) }
        }
        let cached = RaceWidgetCache.readUpcoming()
        let boundaries = cached?.races.flatMap { race in
            [race.end] + (race.sessions?.map(\.start) ?? [])
        } ?? []
        dates += boundaries.map { $0.addingTimeInterval(1) }.filter { $0 > now }.sorted().prefix(12)
        let entries = Set(dates).sorted().map { UpcomingWidgetEntry(date: $0, snapshot: cached?.remaining(at: $0)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func entry(at date: Date) -> UpcomingWidgetEntry {
        UpcomingWidgetEntry(date: date, snapshot: RaceWidgetCache.readUpcoming()?.remaining(at: date))
    }
}

public struct UpcomingWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.upcomingKind, provider: UpcomingWidgetProvider()) { entry in
            UpcomingWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
                .widgetURL(WidgetDestination.calendar.url)
        }
        .configurationDisplayName("未来三站 · Formula 1")
        .description("小尺寸看下一站倒计时，中尺寸查看未来三站。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: UpcomingWidgetEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.races.isEmpty {
            switch family {
            case .systemSmall: small(snapshot)
            default: content(snapshot)
            }
        } else {
            WidgetEmpty(title: "未来赛程", icon: "calendar")
        }
    }

    private func small(_ snapshot: UpcomingWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let race = snapshot.races[0]
        let target = race.raceStart ?? race.start
        return VStack(alignment: .leading, spacing: 5) {
            WidgetHeading(label: "UPCOMING",
                          trailing: stale ? "缓存过期" : race.round.map { "R\($0)" },
                          warning: stale)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(CountryFlag.emoji(for: race.countryCode) ?? "🌐")
                    .font(.system(size: 12))
                Text(race.name)
                    .font(.system(size: 14, weight: .bold)).lineLimit(2).minimumScaleFactor(0.82)
            }
            Text(dateRange(race))
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if target > entry.date {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(ceil(target.timeIntervalSince(entry.date) / 86400)))")
                        .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(widgetRed)
                    Text("天后开赛").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
            } else {
                Text("比赛周进行中")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(widgetRed)
            }
            if let next = race.nextSessionStart, let title = race.nextSessionTitle {
                Text("\(title) · \(next.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private func content(_ snapshot: UpcomingWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let races = Array(snapshot.races.prefix(3))
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("PITPULSE").font(.system(size: 9, weight: .heavy)).tracking(1.6).foregroundStyle(widgetRed)
                Spacer(minLength: 0)
                Text(stale ? "缓存过期" : roundRange(races))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(stale ? .orange : Color.primary.opacity(0.55))
            }
            Text("未来三站").font(.system(size: 12, weight: .bold))
            ForEach(races) { race in row(race) }
            Spacer(minLength: 0)
        }
    }

    private func row(_ race: UpcomingRaceEntry) -> some View {
        HStack(spacing: 7) {
            Text(race.round.map { "R\($0)" } ?? "—")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .frame(width: 32, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
            Text(CountryFlag.emoji(for: race.countryCode) ?? "🌐")
                .font(.system(size: 13)).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(race.name)
                    .font(.system(size: 10.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(dateRange(race))
                    .font(.system(size: 8)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(countdown(race))
                .font(.system(size: 9, weight: .bold)).foregroundStyle(widgetRed)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(widgetRed.opacity(0.12), in: Capsule())
                .fixedSize()
        }
    }

    private func dateRange(_ race: UpcomingRaceEntry) -> String {
        let first = race.start
        let last = race.raceStart ?? race.end
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return WeekendSessionStyle.monthDay(first)
        }
        return "\(WeekendSessionStyle.monthDay(first))–\(WeekendSessionStyle.monthDay(last))"
    }

    private func countdown(_ race: UpcomingRaceEntry) -> String {
        let start = race.raceStart ?? race.start
        guard start > entry.date else { return "进行中" }
        let days = Int(ceil(start.timeIntervalSince(entry.date) / 86400))
        return "\(days) 天"
    }

    private func roundRange(_ races: [UpcomingRaceEntry]) -> String {
        let rounds = races.compactMap(\.round)
        guard let first = rounds.first, let last = rounds.last else { return "F1" }
        return first == last ? "R\(first)" : "R\(first)–R\(last)"
    }
}

#if DEBUG
#Preview("Widget Preview · Upcoming") {
    WidgetSizePreview(families: [.systemSmall, .systemMedium]) { family in
        UpcomingWidgetView(entry: UpcomingWidgetEntry(date: WidgetPreviewData.now, snapshot: WidgetPreviewData.upcoming), previewFamily: family)
    }
}
#endif
#endif
