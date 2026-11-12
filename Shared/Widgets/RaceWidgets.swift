import SwiftUI
import Charts
import WidgetKit
import PitPulseShared

private var widgetBackground: Color {
    #if os(macOS)
    Color(nsColor: .windowBackgroundColor)
    #else
    Color(uiColor: .systemBackground)
    #endif
}

/// Mirrors PulseStyle.red so widgets match the app in both appearances.
private var widgetRed: Color {
    #if os(macOS)
    Color(red: 0.86, green: 0.13, blue: 0.11)
    #else
    Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.98, green: 0.25, blue: 0.23, alpha: 1)
            : UIColor(red: 0.78, green: 0.08, blue: 0.07, alpha: 1)
    })
    #endif
}

private var raceWidgetFamilies: [WidgetFamily] {
    #if os(iOS)
    [.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular]
    #else
    [.systemSmall, .systemMedium, .systemLarge]
    #endif
}

private var scheduleWidgetFamilies: [WidgetFamily] {
    #if os(iOS)
    [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular]
    #else
    [.systemSmall, .systemMedium, .systemLarge]
    #endif
}

struct RaceWeekendEntry: TimelineEntry {
    let date: Date
    let snapshot: RaceWidgetSnapshot?
    let timing: RaceTimingSnapshot?
}

struct RaceWeekendProvider: TimelineProvider {
    func placeholder(in context: Context) -> RaceWeekendEntry { RaceWeekendEntry(date: .now, snapshot: nil, timing: nil) }
    func getSnapshot(in context: Context, completion: @escaping (RaceWeekendEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RaceWeekendEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var dates = [now]
        if let start = current.snapshot?.start, start > now { dates.append(start) }
        if let saved = current.snapshot?.savedAt {
            let expiry = saved.addingTimeInterval(6 * 3600 + 1)
            if expiry > now { dates.append(expiry) }
        }
        if let saved = current.timing?.updatedAt {
            let expiry = saved.addingTimeInterval(91)
            if expiry > now { dates.append(expiry) }
        }
        let entries = dates.sorted().map { RaceWeekendEntry(date: $0, snapshot: current.snapshot, timing: current.timing) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func entry(at date: Date) -> RaceWeekendEntry {
        RaceWeekendEntry(date: date, snapshot: RaceWidgetCache.read(), timing: RaceWidgetCache.readTiming())
    }
}

struct RaceWeekendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.kind, provider: RaceWeekendProvider()) { entry in
            NextRaceWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
                .widgetURL(WidgetDestination.calendar.url)
        }
        .configurationDisplayName("下一场 · Formula 1")
        .description("小尺寸看开赛倒计时，中尺寸查看赛事信息，大尺寸预览比赛周末。")
        .supportedFamilies(raceWidgetFamilies)
    }
}

struct WeekendScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.scheduleKind, provider: RaceWeekendProvider()) { entry in
            WeekendScheduleWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
                .widgetURL(WidgetDestination.calendar.url)
        }
        .configurationDisplayName("比赛周末 · Formula 1")
        .description("小尺寸聚焦最近两场，中尺寸按场次展开，大尺寸显示完整场次安排。")
        .supportedFamilies(scheduleWidgetFamilies)
    }
}

struct LiveTimingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.timingKind, provider: RaceWeekendProvider()) { entry in
            LiveTimingWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
                .widgetURL(WidgetDestination.live.url)
        }
        .configurationDisplayName("实时计时 · Formula 1")
        .description("小尺寸前两位，中尺寸前三位，大尺寸完整前八位。明确标记回放和过期数据。")
        .supportedFamilies(raceWidgetFamilies)
    }
}

private struct WidgetHeading: View {
    var label: String
    var trailing: String? = nil
    var warning = false
    var body: some View {
        HStack(spacing: 4) {
            Text("PITPULSE").font(.system(size: 9, weight: .heavy)).tracking(1.6).foregroundStyle(widgetRed)
            Spacer(minLength: 0)
            Text(trailing ?? label).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                .foregroundStyle(warning ? .orange : Color.primary.opacity(0.55))
        }
    }
}

private struct WidgetEmpty: View {
    let title: String
    let icon: String
    var message = "打开 App 同步数据"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeading(label: "FORMULA 1")
            Spacer(minLength: 0)
            Image(systemName: icon).font(.title3).foregroundStyle(widgetRed)
            Text(title).font(.headline)
            Text(message).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
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

private struct NextRaceWidgetView: View {
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
            HStack { Text("即将开始").font(.caption2.bold()); Spacer(); Text("当地显示时间").font(.system(size: 9)).foregroundStyle(.secondary) }
            ForEach(Array((race.sessions ?? []).filter { $0.start > entry.date }.prefix(5))) { session in
                HStack { Text(session.title).font(.caption.bold()); Spacer(); Text(session.start, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
    }
    private func heading(_ race: RaceWidgetSnapshot) -> some View {
        WidgetHeading(label: "F1", trailing: race.isStale(at: entry.date) ? "缓存过期" : race.round.map { "F1 · R\($0)" }, warning: race.isStale(at: entry.date))
    }
}

private enum WeekendSessionStyle {
    static func category(_ title: String) -> String {
        if title.hasPrefix("FP") { return "PRACTICE" }
        if title.contains("Sprint") || title.contains("冲刺") { return "SPRINT" }
        if title.contains("排位") { return "QUALIFYING" }
        if title.contains("正赛") { return "RACE" }
        return "SESSION"
    }

    static func isRace(_ title: String) -> Bool { title == "正赛" }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func monthDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day())
    }

    static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    static func range(_ sessions: [RaceWidgetSession]) -> String {
        let dates = sessions.map(\.start)
        guard let first = dates.min(), let last = dates.max() else { return "" }
        if Calendar.current.isDate(first, inSameDayAs: last) { return monthDay(first) }
        return "\(monthDay(first))–\(monthDay(last))"
    }
}

private struct WeekendScheduleWidgetView: View {
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
            Text(race.meeting).font(.system(size: 22, weight: .bold)).lineLimit(2).minimumScaleFactor(0.85)
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
        .background(isRace ? widgetRed.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            if isRace {
                RoundedRectangle(cornerRadius: 1.5).fill(widgetRed)
                    .frame(width: 3, height: 20).padding(.leading, -1)
            }
        }
    }
}

private struct LiveTimingWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: RaceWeekendEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    var body: some View {
        if let timing = entry.timing {
            switch family {
            case .systemSmall: small(timing)
            case .systemMedium: medium(timing)
            case .systemLarge: large(timing)
            #if os(iOS)
            case .accessoryInline:
                Text("\(status(timing)) · \(timing.lap) · \(timing.drivers.first?.name ?? timing.session)")
            case .accessoryCircular:
                VStack(spacing: 2) { Image(systemName: "flag.checkered"); Text(timing.isStale(at: entry.date) ? "过期" : timing.lap).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7) }
            #endif
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(timing.session).bold(); Spacer(); Text(timing.lap) }.font(.caption)
                    Text("\(status(timing)) · \(timing.drivers.first?.name ?? timing.meeting)").font(.caption2).lineLimit(1)
                }
            }
        } else { WidgetEmpty(title: "F1 实时计时", icon: "antenna.radiowaves.left.and.right") }
    }
    private func status(_ timing: RaceTimingSnapshot) -> String {
        guard timing.isStale(at: entry.date) else { return timing.status }
        return timing.status.contains("回放") ? "回放 · 数据过期" : "数据过期"
    }
    private func small(_ timing: RaceTimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeading(label: status(timing), warning: timing.isStale(at: entry.date))
            Text(timing.lap).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1)
            Text(timing.meeting).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            ForEach(Array(timing.drivers.prefix(2))) { row in driverRow(row, compact: true) }
        }
    }
    private func medium(_ timing: RaceTimingSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PITPULSE").font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundStyle(widgetRed)
                Text(timing.session.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                Text(timing.lap).font(.title2.bold().monospacedDigit())
                Text(status(timing)).font(.system(size: 9, weight: .semibold)).foregroundStyle(timing.isStale(at: entry.date) ? .orange : widgetRed)
            }.frame(width: 95, alignment: .leading)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text(timing.meeting).font(.system(size: 10, weight: .semibold)).lineLimit(1).foregroundStyle(.secondary)
                ForEach(Array(timing.drivers.prefix(3))) { row in driverRow(row, compact: true) }
            }.frame(maxWidth: .infinity)
        }
    }
    private func large(_ timing: RaceTimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeading(label: status(timing), warning: timing.isStale(at: entry.date))
            HStack(alignment: .firstTextBaseline) {
                Text(timing.meeting).font(.headline).lineLimit(2)
                Spacer(minLength: 8)
                Text(timing.lap).font(.title3.bold().monospacedDigit())
            }
            Text("距离领跑车手 · 秒").font(.system(size: 9)).foregroundStyle(.secondary)
            Chart(Array(timing.drivers.prefix(8))) { row in
                if let gap = widgetGap(row.gap) {
                    BarMark(x: .value("秒差", gap), y: .value("车手", MotorsportAssetName.abbreviation(row.name)))
                        .foregroundStyle(widgetRed).cornerRadius(2)
                        .annotation(position: .trailing) { Text(gap == 0 ? "P1" : String(format: "+%.1f", gap)).font(.system(size: 8).monospacedDigit()) }
                }
            }.frame(height: 135).chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            Divider()
            ForEach(Array(timing.drivers.prefix(3))) { row in driverRow(row, compact: false) }
            Spacer(minLength: 0)
            HStack { Text(timing.session); Spacer(); Text("更新 "); Text(timing.updatedAt, style: .time) }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
    private func widgetGap(_ text: String) -> Double? {
        if text.uppercased() == "LEADER" { return 0 }
        guard let value = Double(text.replacingOccurrences(of: "+", with: "")), value.isFinite, value >= 0 else { return nil }
        return value
    }
    private func driverRow(_ driver: RaceTimingDriver, compact: Bool) -> some View {
        HStack(spacing: compact ? 5 : 9) {
            Text(driver.position.map(String.init) ?? "—").fontWeight(.semibold).frame(width: compact ? 10 : 16, alignment: .leading)
            Image(MotorsportAssetName.helmetName(name: driver.name, season: 2026)).resizable().scaledToFit()
                .frame(width: compact ? 18 : 25, height: compact ? 16 : 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(MotorsportAssetName.abbreviation(driver.name)).fontWeight(.bold).lineLimit(1)
                if !compact, let asset = driver.teamAsset {
                    Image(asset).resizable().scaledToFit().frame(width: 18, height: 8).accessibilityHidden(true)
                }
            }
            Spacer(minLength: 2)
            Text(driver.gap).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if !compact { Text(driver.tire ?? "—").font(.system(size: 9, weight: .bold)).foregroundStyle(widgetRed).frame(width: 16) }
        }.font(.system(size: compact ? 10 : 11))
    }
}


// MARK: - Standings

struct StandingsWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: StandingsWidgetSnapshot?
}

struct StandingsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> StandingsWidgetEntry {
        StandingsWidgetEntry(date: .now, snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (StandingsWidgetEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StandingsWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var dates = [now]
        if let saved = current.snapshot?.savedAt {
            let expiry = saved.addingTimeInterval(6 * 3600 + 1)
            if expiry > now { dates.append(expiry) }
        }
        let entries = dates.sorted().map { StandingsWidgetEntry(date: $0, snapshot: current.snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func entry(at date: Date) -> StandingsWidgetEntry {
        StandingsWidgetEntry(date: date, snapshot: RaceWidgetCache.readStandings())
    }
}

struct StandingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.standingsKind, provider: StandingsWidgetProvider()) { entry in
            StandingsWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
        }
        .configurationDisplayName("车手积分 · Formula 1")
        .description("小尺寸看榜首，中尺寸查看前五名与和榜首的差距。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct StandingsWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: StandingsWidgetEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.drivers.isEmpty {
            switch family {
            case .systemSmall: small(snapshot)
            default: content(snapshot)
            }
        } else {
            WidgetEmpty(title: "车手积分", icon: "trophy.fill")
        }
    }

    private func small(_ snapshot: StandingsWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let leader = snapshot.drivers[0]
        let runnerUp = snapshot.drivers.count > 1 ? snapshot.drivers[1] : nil
        return VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(label: "STANDINGS",
                          trailing: stale ? "缓存过期" : "\(snapshot.season)",
                          warning: stale)
            HStack(spacing: 7) {
                Image(MotorsportAssetName.helmetName(driverID: leader.driverID, name: leader.name, season: snapshot.season))
                    .resizable().scaledToFit().frame(width: 42, height: 36).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MotorsportAssetName.abbreviation(leader.name))
                        .font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Text(leader.team)
                        .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(leader.points.rounded()))")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(widgetRed)
                Text("积分").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Text("领先 P2").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(runnerUp.map { "+\(Int($0.gapToLeader.rounded()))" } ?? "—")
                    .font(.system(size: 10, weight: .bold)).monospacedDigit()
            }
        }
    }

    private func content(_ snapshot: StandingsWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let season = snapshot.season
        return VStack(alignment: .leading, spacing: 4) {
            WidgetHeading(label: "STANDINGS",
                          trailing: stale ? "缓存过期" : "\(season)",
                          warning: stale)
            HStack(spacing: 5) {
                Text("车手").font(.system(size: 11, weight: .bold))
                Spacer(minLength: 4)
                Text("积分").font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                Text("与榜首").font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
            }
            ForEach(Array(snapshot.drivers.prefix(5))) { driver in
                row(driver, season: season)
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ driver: WidgetStandingDriver, season: Int) -> some View {
        let isLeader = driver.position == 1
        return HStack(spacing: 5) {
            Text("\(driver.position)")
                .font(.system(size: 9, weight: .bold)).monospacedDigit()
                .foregroundStyle(isLeader ? widgetRed : .secondary)
                .frame(width: 12, alignment: .leading)
            Image(MotorsportAssetName.helmetName(driverID: driver.driverID, name: driver.name, season: season))
                .resizable().scaledToFit().frame(width: 20, height: 16).accessibilityHidden(true)
            Text(MotorsportAssetName.abbreviation(driver.name))
                .font(.system(size: 10, weight: .bold)).lineLimit(1)
                .frame(width: 27, alignment: .leading)
            Text(driver.team)
                .font(.system(size: 7.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 2)
            Text("\(Int(driver.points.rounded()))")
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
                .frame(width: 30, alignment: .trailing)
            Text(gapText(driver.gapToLeader))
                .font(.system(size: 8, weight: .medium)).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 1.5).padding(.horizontal, 4)
        .background(isLeader ? widgetRed.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) {
            if isLeader {
                RoundedRectangle(cornerRadius: 1.5).fill(widgetRed)
                    .frame(width: 2.5, height: 14).padding(.leading, -1)
            }
        }
    }

    private func gapText(_ gap: Double) -> String {
        let value = Int(gap.rounded())
        return value <= 0 ? "—" : "−\(value)"
    }
}

// MARK: - Favorite driver

struct FavoriteDriverWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: FavoriteDriverWidgetSnapshot?
}

struct FavoriteDriverWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavoriteDriverWidgetEntry {
        FavoriteDriverWidgetEntry(date: .now, snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (FavoriteDriverWidgetEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoriteDriverWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var dates = [now]
        if let saved = current.snapshot?.savedAt {
            let expiry = saved.addingTimeInterval(6 * 3600 + 1)
            if expiry > now { dates.append(expiry) }
        }
        let entries = dates.sorted().map { FavoriteDriverWidgetEntry(date: $0, snapshot: current.snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func entry(at date: Date) -> FavoriteDriverWidgetEntry {
        FavoriteDriverWidgetEntry(date: date, snapshot: RaceWidgetCache.readFavoriteDriver())
    }
}

struct FavoriteDriverWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.favoriteDriverKind, provider: FavoriteDriverWidgetProvider()) { entry in
            FavoriteDriverWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
        }
        .configurationDisplayName("我的车手 · Formula 1")
        .description("小尺寸看排名与积分，中尺寸看近期比赛，大尺寸展开近三场与赛季数据。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct FavoriteDriverWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: FavoriteDriverWidgetEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall: small(snapshot)
            case .systemMedium: medium(snapshot)
            default: large(snapshot)
            }
        } else {
            WidgetEmpty(title: "我的车手", icon: "star.fill", message: "在 App 设置中选择喜欢车手")
        }
    }

    private func small(_ snapshot: FavoriteDriverWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let driver = snapshot.driver
        return VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(label: "MY DRIVER",
                          trailing: stale ? "缓存过期" : "\(snapshot.season)",
                          warning: stale)
            HStack(spacing: 7) {
                helmet(driver, season: snapshot.season, size: CGSize(width: 42, height: 36))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("P\(driver.position)")
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(widgetRed)
                        Text(MotorsportAssetName.abbreviation(driver.name))
                            .font(.system(size: 16, weight: .bold)).lineLimit(1)
                    }
                    Text(driver.team)
                        .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(driver.points.rounded()))")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(widgetRed)
                Text("积分").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Text(gapLabel(snapshot)).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(gapText(snapshot)).font(.system(size: 10, weight: .bold)).monospacedDigit()
            }
        }
    }

    private func medium(_ snapshot: FavoriteDriverWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let driver = snapshot.driver
        let last = snapshot.recentRaces.first
        let form = Array(snapshot.recentRaces.prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            WidgetHeading(label: "MY DRIVER",
                          trailing: stale ? "缓存过期" : "F1 · \(snapshot.season)",
                          warning: stale)
            HStack(spacing: 7) {
                helmet(driver, season: snapshot.season, size: CGSize(width: 40, height: 32))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("P\(driver.position)")
                            .font(.system(size: 11, weight: .heavy)).foregroundStyle(widgetRed)
                        Text(MotorsportAssetName.abbreviation(driver.name))
                            .font(.system(size: 15, weight: .bold)).lineLimit(1)
                    }
                    Text(driver.team)
                        .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(driver.points.rounded()))")
                        .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(widgetRed)
                    Text("积分").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            Divider()
            if let last {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("上站 · \(last.meeting)")
                        .font(.system(size: 9, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(last.date, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    raceResultStat("名次", finishText(last), highlight: true)
                    Divider().frame(height: 20)
                    raceResultStat("积分", pointsText(last))
                    Divider().frame(height: 20)
                    raceResultStat("最快圈", last.fastestLap ?? "—")
                    Divider().frame(height: 20)
                    raceResultStat("时间", last.gap ?? "—")
                }
            } else {
                Text("近期比赛数据将在完赛后更新")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            if form.count > 1 {
                HStack(spacing: 4) {
                    Text("近\(form.count)场")
                        .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                    ForEach(form) { race in
                        Text(finishText(race))
                            .font(.system(size: 8, weight: .bold)).monospacedDigit()
                            .foregroundStyle(race.position == 1 ? widgetRed : .primary)
                            .padding(.horizontal, 4).padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    Spacer(minLength: 2)
                    Text("\(recentPoints(form)) 分")
                        .font(.system(size: 9, weight: .bold)).monospacedDigit().foregroundStyle(widgetRed)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func large(_ snapshot: FavoriteDriverWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let driver = snapshot.driver
        let recent = Array(snapshot.recentRaces.prefix(3))
        return VStack(alignment: .leading, spacing: 8) {
            WidgetHeading(label: "MY DRIVER",
                          trailing: stale ? "缓存过期" : "F1 · \(snapshot.season)",
                          warning: stale)
            HStack(alignment: .center, spacing: 12) {
                helmet(driver, season: snapshot.season, size: CGSize(width: 80, height: 70))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("P\(driver.position)")
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(widgetRed)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(widgetRed.opacity(0.12), in: Capsule())
                        Text(MotorsportAssetName.abbreviation(driver.name))
                            .font(.system(size: 24, weight: .bold)).lineLimit(1)
                    }
                    Text(driver.name)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(driver.team)
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(driver.points.rounded()))")
                        .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(widgetRed)
                    Text("积分").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 0) {
                stat("分站冠军", "\(snapshot.wins)")
                Divider().frame(height: 26)
                stat(recent.isEmpty ? "近期积分" : "近\(recent.count)场积分",
                     recent.isEmpty ? "—" : "\(recentPoints(recent))")
                Divider().frame(height: 26)
                stat(gapLabel(snapshot), gapText(snapshot), highlight: driver.position != 1)
            }
            seasonProgress(driver)
            Divider()
            HStack {
                Text("近期比赛").font(.system(size: 10, weight: .bold))
                Spacer()
                if !recent.isEmpty {
                    Text("最近 \(recent.count) 场").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            if recent.isEmpty {
                Text("打开 App 同步近期比赛数据")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { race in
                        recentRaceRow(race)
                        if race.id != recent.last?.id { Divider().padding(.leading, 34) }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("近期比赛 · \(snapshot.driver.team)")
                Spacer()
                if stale {
                    Text("缓存数据")
                } else {
                    Text("更新 ")
                    Text(snapshot.savedAt, style: .time)
                }
            }.font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }

    private func seasonProgress(_ driver: WidgetStandingDriver) -> some View {
        let leaderPoints = driver.points + driver.gapToLeader
        let share = leaderPoints > 0 ? min(1, max(0, driver.points / leaderPoints)) : 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("赛季积分")
                Spacer()
                Text("\(Int(driver.points.rounded())) / \(Int(leaderPoints.rounded()))")
            }.font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(widgetRed).frame(width: geometry.size.width * share)
                }
            }.frame(height: 5)
        }
    }

    private func helmet(_ driver: WidgetStandingDriver, season: Int, size: CGSize) -> some View {
        Image(MotorsportAssetName.helmetName(driverID: driver.driverID, name: driver.name, season: season))
            .resizable().scaledToFit().frame(width: size.width, height: size.height).accessibilityHidden(true)
    }

    private func recentRaceRow(_ race: FavoriteRaceEntry) -> some View {
        HStack(spacing: 8) {
            Text(race.round.map { "R\($0)" } ?? "—")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .frame(width: 28, alignment: .leading).lineLimit(1)
            VStack(alignment: .leading, spacing: 1) {
                Text(shortMeeting(race.meeting))
                    .font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(race.date, format: .dateTime.month(.abbreviated).day())
                    if let lap = race.fastestLap { Text("· 最快圈 \(lap)") }
                }.font(.system(size: 7.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(race.gap ?? "—")
                .font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
            Text(finishText(race))
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(race.position == 1 ? widgetRed : .primary)
                .frame(width: 32, alignment: .trailing)
            Text(pointsText(race))
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 5).padding(.horizontal, 4)
    }

    private func raceResultStat(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 7.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(highlight ? widgetRed : .primary)
                .lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity)
    }

    private func shortMeeting(_ name: String) -> String {
        name.replacingOccurrences(of: " Grand Prix", with: "")
            .replacingOccurrences(of: " GP", with: "")
    }

    private func finishText(_ race: FavoriteRaceEntry) -> String {
        race.position.map { "P\($0)" } ?? race.classification ?? "—"
    }

    private func pointsText(_ race: FavoriteRaceEntry) -> String {
        race.points.map { "\(Int($0.rounded()))" } ?? "—"
    }

    private func recentPoints(_ races: [FavoriteRaceEntry]) -> Int {
        Int(races.compactMap(\.points).reduce(0, +).rounded())
    }

    private func gapLabel(_ snapshot: FavoriteDriverWidgetSnapshot) -> String {
        snapshot.driver.position == 1 ? "领先 P2" : "落后榜首"
    }

    private func gapText(_ snapshot: FavoriteDriverWidgetSnapshot) -> String {
        if snapshot.driver.position == 1 {
            return snapshot.gapToBehind.map { "+\(Int($0.rounded()))" } ?? "—"
        }
        let value = Int(snapshot.driver.gapToLeader.rounded())
        return value <= 0 ? "—" : "−\(value)"
    }

    private func stat(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.system(size: 14, weight: .bold)).monospacedDigit()
                .foregroundStyle(highlight ? widgetRed : .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }
}

// MARK: - Last race

struct LastRaceWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: LastRaceWidgetSnapshot?
}

struct LastRaceWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LastRaceWidgetEntry {
        LastRaceWidgetEntry(date: .now, snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (LastRaceWidgetEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LastRaceWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var dates = [now]
        if let saved = current.snapshot?.savedAt {
            let expiry = saved.addingTimeInterval(6 * 3600 + 1)
            if expiry > now { dates.append(expiry) }
        }
        let entries = dates.sorted().map { LastRaceWidgetEntry(date: $0, snapshot: current.snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func entry(at date: Date) -> LastRaceWidgetEntry {
        LastRaceWidgetEntry(date: date, snapshot: RaceWidgetCache.readLastRace())
    }
}

struct LastRaceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.lastRaceKind, provider: LastRaceWidgetProvider()) { entry in
            LastRaceWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
        }
        .configurationDisplayName("上站结果 · Formula 1")
        .description("中尺寸看领奖台与比赛数字，大尺寸展开完整结果。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct LastRaceWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: LastRaceWidgetEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.podium.isEmpty {
            switch family {
            case .systemMedium: medium(snapshot)
            default: content(snapshot)
            }
        } else {
            WidgetEmpty(title: "上站结果", icon: "flag.checkered")
        }
    }

    private func medium(_ snapshot: LastRaceWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let season = snapshot.season ?? Calendar.current.component(.year, from: snapshot.raceDate ?? entry.date)
        let podium = Array(snapshot.podium.prefix(3))
        return VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(label: "LAST RACE",
                          trailing: stale ? "缓存过期" : snapshot.round.map { "F1 · R\($0)" },
                          warning: stale)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(snapshot.meeting)
                    .font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text(raceMeta(snapshot))
                    .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 0) {
                ForEach(Array(podium.enumerated()), id: \.element.id) { index, row in
                    podiumCompact(row, season: season)
                    if index < podium.count - 1 { Divider().frame(height: 38) }
                }
            }
            Divider()
            HStack(spacing: 0) {
                stat("最快圈", snapshot.fastestLap ?? "—", highlight: true)
                Divider().frame(height: 22)
                stat("圈数", snapshot.laps.map(String.init) ?? "—")
                Divider().frame(height: 22)
                if let safetyCars = snapshot.safetyCars {
                    stat("安全车", "\(safetyCars)")
                } else {
                    stat("冠军积分", podium.first?.points.map { "\(Int($0.rounded()))" } ?? "—")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func raceMeta(_ snapshot: LastRaceWidgetSnapshot) -> String {
        var parts: [String] = []
        if let date = snapshot.raceDate {
            parts.append(date.formatted(.dateTime.month(.abbreviated).day()))
        }
        parts.append(snapshot.session)
        return parts.joined(separator: " · ")
    }

    private func podiumCompact(_ row: LastRacePodiumEntry, season: Int) -> some View {
        let isWinner = row.position == 1
        return VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text("P\(row.position)")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(isWinner ? widgetRed : .secondary)
                Image(MotorsportAssetName.helmetName(driverID: row.driverID, name: row.name, season: season))
                    .resizable().scaledToFit().frame(width: 26, height: 22).accessibilityHidden(true)
                Text(MotorsportAssetName.abbreviation(row.name))
                    .font(.system(size: 10, weight: .bold)).lineLimit(1)
            }
            Text(row.time)
                .font(.system(size: 9, weight: .semibold)).monospacedDigit()
                .foregroundStyle(isWinner ? widgetRed : .primary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity)
    }

    private func content(_ snapshot: LastRaceWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let season = snapshot.season ?? Calendar.current.component(.year, from: snapshot.raceDate ?? entry.date)
        let podium = Array(snapshot.podium.prefix(3))
        return VStack(alignment: .leading, spacing: 9) {
            WidgetHeading(label: "LAST RACE",
                          trailing: stale ? "缓存过期" : snapshot.round.map { "F1 · R\($0)" },
                          warning: stale)
            Text(snapshot.meeting)
                .font(.system(size: 22, weight: .bold)).lineLimit(2).minimumScaleFactor(0.85)
            HStack(spacing: 6) {
                if let date = snapshot.raceDate {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                }
                Text("·")
                Text(snapshot.session)
                Spacer(minLength: 4)
                Text("已结束")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(widgetRed)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(widgetRed.opacity(0.12), in: Capsule())
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(Array(podium.enumerated()), id: \.element.id) { index, row in
                    podiumColumn(row, season: season)
                    if index < podium.count - 1 { Divider().frame(height: 84) }
                }
            }

            Divider()
            HStack(spacing: 0) {
                stat("最快圈", snapshot.fastestLap ?? "—", highlight: true)
                Divider().frame(height: 28)
                stat("圈数", snapshot.laps.map(String.init) ?? "—")
                Divider().frame(height: 28)
                if let safetyCars = snapshot.safetyCars {
                    stat("安全车", "\(safetyCars)")
                } else {
                    stat("冠军积分", podium.first?.points.map { "\(Int($0.rounded()))" } ?? "—")
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("比赛结果")
                Spacer()
                if stale {
                    Text("缓存数据")
                } else {
                    Text("更新 ")
                    Text(snapshot.savedAt, style: .time)
                }
            }.font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }

    private func podiumColumn(_ row: LastRacePodiumEntry, season: Int) -> some View {
        let isWinner = row.position == 1
        return VStack(spacing: 3) {
            Text("P\(row.position)")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(isWinner ? widgetRed : .secondary)
            Image(MotorsportAssetName.helmetName(driverID: row.driverID, name: row.name, season: season))
                .resizable().scaledToFit().frame(width: 52, height: 46).accessibilityHidden(true)
            Text(MotorsportAssetName.abbreviation(row.name))
                .font(.system(size: 11, weight: .bold)).lineLimit(1)
            Text(row.time)
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(isWinner ? widgetRed : .primary)
                .lineLimit(1).minimumScaleFactor(0.62)
            Text(row.team)
                .font(.system(size: 7.5)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }

    private func stat(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold)).monospacedDigit()
                .foregroundStyle(highlight ? widgetRed : .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }
}

// MARK: - Upcoming races

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
        let entries = dates.sorted().map { UpcomingWidgetEntry(date: $0, snapshot: current.snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func entry(at date: Date) -> UpcomingWidgetEntry {
        UpcomingWidgetEntry(date: date, snapshot: RaceWidgetCache.readUpcoming())
    }
}

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.upcomingKind, provider: UpcomingWidgetProvider()) { entry in
            UpcomingWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
                .widgetURL(WidgetDestination.calendar.url)
        }
        .configurationDisplayName("未来三站 · Formula 1")
        .description("小尺寸看下一站倒计时，中尺寸查看未来三站。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct UpcomingWidgetView: View {
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

#if DEBUG && os(iOS)
/// Uses the extension renderers and real App Group data, never sample race data.
struct WidgetPreviewGallery: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPage: Int? = 0
    @State private var showInstructions = false
    @State private var entry = RaceWeekendEntry(date: .now, snapshot: RaceWidgetCache.read(), timing: RaceWidgetCache.readTiming())
    @State private var standingsEntry = StandingsWidgetEntry(date: .now, snapshot: RaceWidgetCache.readStandings())
    @State private var favoriteDriverEntry = FavoriteDriverWidgetEntry(date: .now, snapshot: RaceWidgetCache.readFavoriteDriver())
    @State private var lastRaceEntry = LastRaceWidgetEntry(date: .now, snapshot: RaceWidgetCache.readLastRace())
    @State private var upcomingEntry = UpcomingWidgetEntry(date: .now, snapshot: RaceWidgetCache.readUpcoming())

    init() {
        let initial = ProcessInfo.processInfo.environment["PITPULSE_WIDGET_PAGE"].flatMap(Int.init) ?? 0
        _selectedPage = State(initialValue: initial)
    }

    private struct PreviewPage {
        let kind: Int
        let family: WidgetFamily
    }

    private let pages: [PreviewPage] = [
        .init(kind: 0, family: .systemSmall), .init(kind: 0, family: .systemMedium), .init(kind: 0, family: .systemLarge),
        .init(kind: 1, family: .systemSmall), .init(kind: 1, family: .systemMedium), .init(kind: 1, family: .systemLarge),
        .init(kind: 2, family: .systemSmall), .init(kind: 2, family: .systemMedium),
        .init(kind: 3, family: .systemMedium), .init(kind: 3, family: .systemLarge),
        .init(kind: 4, family: .systemSmall), .init(kind: 4, family: .systemMedium),
        .init(kind: 5, family: .systemSmall), .init(kind: 5, family: .systemMedium), .init(kind: 5, family: .systemLarge)
    ]
    private var page: Int { min(max(selectedPage ?? 0, 0), pages.count - 1) }
    private var kind: Int { kind(for: page) }
    private var scheme: ColorScheme { systemScheme }
    private let titles = ["下一场 · Formula 1", "比赛周末 · Formula 1",
                          "车手积分 · Formula 1", "上站结果 · Formula 1", "未来三站 · Formula 1",
                          "我的车手 · Formula 1"]
    private let descriptions = [
        "开赛倒计时、赛事信息与即将到来的比赛周末。",
        "从最近场次到完整周末，按你的桌面空间选择。",
        "小尺寸看榜首，中尺寸查看前五名与和榜首的差距。",
        "中尺寸看领奖台与比赛数字，大尺寸展开完整结果。",
        "小尺寸看下一站倒计时，中尺寸查看未来三站。",
        "小尺寸看排名与积分，中尺寸看近期比赛，大尺寸展开近三场与赛季数据。"
    ]
    private let sizes = ["小尺寸", "中尺寸", "大尺寸"]

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text(titles[kind]).font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(descriptions[kind]).font(.subheadline)
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(sizeLabel(page)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
            .layoutPriority(1)

            GeometryReader { geometry in
                let width = max(338, geometry.size.width - 64)
                let height = max(1, geometry.size.height)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            preview(index: index)
                                .frame(width: width, height: height)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, max(0, (geometry.size.width - width) / 2), for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always, anchor: .center))
                .scrollPosition(id: $selectedPage, anchor: .center)
                .scrollClipDisabled()
                .accessibilityLabel("组件陈列，左右滑动浏览")
                .accessibilityValue("第 \(page + 1) 页，共 \(pages.count) 页")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: select(min(page + 1, pages.count - 1))
                    case .decrement: select(max(page - 1, 0))
                    @unknown default: break
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Button { select(index) } label: {
                        Circle().fill(index == page ? Color.primary : Color.secondary.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .frame(width: 14, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(titles[kind(for: index)])，\(sizeLabel(index))")
                    .accessibilityAddTraits(index == page ? [.isSelected] : [])
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("组件预览")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showInstructions = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("如何添加小组件")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("关闭组件预览")
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) }
                catch { return }
                guard !Task.isCancelled else { return }
                refresh()
            }
        }
        .alert("添加 PitPulse 小组件", isPresented: $showInstructions) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("长按 iPhone 主屏幕空白处，选择「编辑」→「添加小组件」，搜索 PitPulse，再左右滑动选择类型与尺寸并添加。App 内预览不会直接添加桌面组件。")
        }
    }

    private func select(_ index: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { selectedPage = index }
    }

    private func refresh() {
        let now = Date()
        entry = RaceWeekendEntry(date: now, snapshot: RaceWidgetCache.read(), timing: RaceWidgetCache.readTiming())
        standingsEntry = StandingsWidgetEntry(date: now, snapshot: RaceWidgetCache.readStandings())
        favoriteDriverEntry = FavoriteDriverWidgetEntry(date: now, snapshot: RaceWidgetCache.readFavoriteDriver())
        lastRaceEntry = LastRaceWidgetEntry(date: now, snapshot: RaceWidgetCache.readLastRace())
        upcomingEntry = UpcomingWidgetEntry(date: now, snapshot: RaceWidgetCache.readUpcoming())
    }

    private func kind(for index: Int) -> Int { pages[index].kind }

    private func size(for index: Int) -> Int {
        switch family(for: index) {
        case .systemSmall: 0
        case .systemMedium: 1
        default: 2
        }
    }

    private func sizeLabel(_ index: Int) -> String { sizes[size(for: index)] }

    private func family(for index: Int) -> WidgetFamily { pages[index].family }

    private func previewSize(_ size: Int) -> CGSize {
        size == 0 ? CGSize(width: 158, height: 158)
            : size == 1 ? CGSize(width: 338, height: 158) : CGSize(width: 338, height: 354)
    }

    private func preview(index: Int) -> some View {
        let size = size(for: index)
        let native = previewSize(size)
        return Group {
            switch kind(for: index) {
            case 1: WeekendScheduleWidgetView(entry: entry, previewFamily: family(for: index))
            case 2: StandingsWidgetView(entry: standingsEntry, previewFamily: family(for: index))
            case 3: LastRaceWidgetView(entry: lastRaceEntry, previewFamily: family(for: index))
            case 4: UpcomingWidgetView(entry: upcomingEntry, previewFamily: family(for: index))
            case 5: FavoriteDriverWidgetView(entry: favoriteDriverEntry, previewFamily: family(for: index))
            default: NextRaceWidgetView(entry: entry, previewFamily: family(for: index))
            }
        }
        .padding(16)
        .frame(width: native.width, height: native.height)
        .environment(\.colorScheme, scheme)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.25 : 0.12), radius: 12, y: 8)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : 2), axis: (x: 1, y: 0, z: 0), perspective: 0.25)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : -3), axis: (x: 0, y: 1, z: 0), perspective: 0.25)
        .rotationEffect(.degrees(reduceMotion ? 0 : 1))
        .offset(y: reduceMotion ? 0 : 3)
        .environment(\.colorScheme, scheme)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titles[kind(for: index)])，\(sizeLabel(index))预览")
    }
}
#endif
