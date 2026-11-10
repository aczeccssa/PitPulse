import ActivityKit
import SwiftUI
import Charts
import WidgetKit
import PitPulseShared

struct PitPulseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PitPulseActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.seriesTitle.uppercased()).font(.caption2.bold()).tracking(2).foregroundStyle(.red)
                        Text(context.state.meetingName).font(.headline).lineLimit(1)
                        Text(context.state.sessionName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(context.state.lapLabel).font(.title3.bold().monospacedDigit())
                        ActivityStatus(state: context.state, expired: context.isStale)
                    }
                }
                Divider().overlay(Color.primary.opacity(0.1))
                ActivityPayloadView(state: context.state)
                Text(context.state.trackLabel ?? "等待赛道状态").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(16)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "pitpulse://live"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.sessionName.uppercased()).font(.caption2.bold()).foregroundStyle(.red)
                        Text(context.state.lapLabel).font(.caption.bold().monospacedDigit())
                    }.padding(.leading, 12).padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityStatus(state: context.state, expired: context.isStale).padding(.trailing, 10).padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.meetingName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        ActivityPayloadView(state: context.state)
                        HStack {
                            Image(systemName: "flag.fill").foregroundStyle(.red)
                            Text(context.state.trackLabel ?? "等待赛道状态").lineLimit(1)
                            Spacer()
                            Text(context.state.isStale || context.isStale ? "数据过期" : (context.state.updatedLabel ?? ""))
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 12).environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(MotorsportAssetName.seriesLogoName(isWec: context.attributes.seriesTitle == "FIA WEC")).resizable().scaledToFit().frame(width: 24, height: 14)
                    Text(context.state.presentation == IslandContentMode.favorite.rawValue ? (context.state.favoriteName.map(MotorsportAssetName.abbreviation) ?? "收藏") : context.state.sessionName).font(.system(size: 9, weight: .bold)).lineLimit(1)
                }.foregroundStyle(.red)
            } compactTrailing: {
                Text(context.isStale || context.state.isStale ? "过期" : compactValue(context.state))
                    .font(.caption2.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(context.isStale || context.state.isStale ? .orange : .white)
            } minimal: {
                Image(systemName: context.isStale || context.state.isStale ? "clock.badge.exclamationmark" : "flag.checkered")
                    .foregroundStyle(context.isStale || context.state.isStale ? .orange : .red)
            }
            .keylineTint(.red)
            .widgetURL(URL(string: "pitpulse://live"))
        }
    }
    private func compactValue(_ state: PitPulseActivityAttributes.ContentState) -> String {
        if state.presentation == IslandContentMode.favorite.rawValue { return state.favoritePosition.map { "P\($0)" } ?? "—" }
        if state.presentation == IslandContentMode.battle.rawValue { return state.challengerGap ?? state.lapLabel }
        return state.lapLabel
    }
}

private struct ActivityStatus: View {
    let state: PitPulseActivityAttributes.ContentState
    let expired: Bool
    var body: some View {
        Text(state.isStale || expired ? "数据过期" : state.statusLabel)
            .font(.system(size: 10, weight: .bold)).lineLimit(1)
            .foregroundStyle(state.isStale || expired ? .orange : .red)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct ActivityPayloadView: View {
    let state: PitPulseActivityAttributes.ContentState
    var body: some View {
        switch state.presentation.flatMap(IslandContentMode.init(rawValue:)) ?? .overview {
        case .battle: BattleView(state: state)
        case .favorite:
            HStack(spacing: 10) {
                if let asset = state.favoriteAsset { Image(asset).resizable().scaledToFit().frame(width: 42, height: 36).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 4) {
                    Label("喜欢的车手", systemImage: "star.fill").font(.system(size: 9)).foregroundStyle(.red)
                    Text(state.favoriteName ?? "请在 App 中选择车手").font(.caption.bold()).lineLimit(1)
                    if state.favoriteName != nil && state.favoritePosition == nil { Text("不在当前比赛中").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 4)
                Text(state.favoritePosition.map { "P\($0)" } ?? "—").font(.headline.monospacedDigit())
                Text(state.favoriteGap ?? "—").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        case .overview:
            HStack {
                Label(state.trackLabel ?? "等待赛道状态", systemImage: "flag.fill").font(.caption).lineLimit(1)
                Spacer()
                Text("\(state.driverCount) 位车手").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct BattleView: View {
    let state: PitPulseActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 8) {
            driver(state.leaderName, asset: state.leaderAsset, rank: "P1")
            Spacer(minLength: 4)
            Text(state.challengerGap ?? state.leaderGap ?? "—")
                .font(.caption.bold().monospacedDigit()).foregroundStyle(.red).lineLimit(1)
            Spacer(minLength: 4)
            if state.challengerName != nil { driver(state.challengerName, asset: state.challengerAsset, rank: "P2") }
        }
    }
    private func driver(_ name: String?, asset: String?, rank: String) -> some View {
        HStack(spacing: 5) {
            if let asset { Image(asset).resizable().scaledToFit().frame(width: 40, height: 30).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 3) {
                Text(name.map(MotorsportAssetName.abbreviation) ?? "—").font(.caption2.bold()).lineLimit(1)
                Text(rank).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
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
            NextRaceWidgetView(entry: entry).containerBackground(Color(uiColor: .systemBackground), for: .widget)
                .widgetURL(URL(string: "pitpulse://calendar"))
        }
        .configurationDisplayName("下一场 · Formula 1")
        .description("小尺寸看开赛倒计时，中尺寸查看赛事信息，大尺寸预览比赛周末。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct WeekendScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.scheduleKind, provider: RaceWeekendProvider()) { entry in
            WeekendScheduleWidgetView(entry: entry).containerBackground(Color(uiColor: .systemBackground), for: .widget)
                .widgetURL(URL(string: "pitpulse://calendar"))
        }
        .configurationDisplayName("比赛周末 · Formula 1")
        .description("小尺寸聚焦最近两场，中尺寸展开周末时间轴，大尺寸显示完整场次安排。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct LiveTimingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.timingKind, provider: RaceWeekendProvider()) { entry in
            LiveTimingWidgetView(entry: entry).containerBackground(Color(uiColor: .systemBackground), for: .widget)
                .widgetURL(URL(string: "pitpulse://live?series=f1"))
        }
        .configurationDisplayName("实时计时 · Formula 1")
        .description("小尺寸前两位，中尺寸前三位，大尺寸完整前八位。明确标记回放和过期数据。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

private struct WidgetHeading: View {
    var label: String
    var trailing: String? = nil
    var warning = false
    var body: some View {
        HStack(spacing: 4) {
            Text("PITPULSE").font(.system(size: 9, weight: .heavy)).tracking(1.6).foregroundStyle(.red)
            Spacer(minLength: 0)
            Text(trailing ?? label).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                .foregroundStyle(warning ? .orange : Color.primary.opacity(0.55))
        }
    }
}

private struct WidgetEmpty: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeading(label: "FORMULA 1")
            Spacer(minLength: 0)
            Image(systemName: icon).font(.title3).foregroundStyle(.red)
            Text(title).font(.headline)
            Text("打开 App 同步数据").font(.caption2).foregroundStyle(.secondary)
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
            case .accessoryInline:
                Text("\(race.session) · \(race.start.formatted(date: .omitted, time: .shortened)) · \(race.meeting)")
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "flag.checkered").font(.caption)
                    if race.start > entry.date {
                        Text("\(max(0, Int(race.start.timeIntervalSince(entry.date) / 86400)))天").font(.caption.bold())
                    } else { Text("更新").font(.caption2) }
                }.accessibilityLabel("下一场 \(race.session)")
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
            HStack { Text(race.session).foregroundStyle(.red); Text(race.start, format: .dateTime.month(.twoDigits).day().hour().minute()) }
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
                    Text(row.title).font(.caption.bold()).foregroundStyle(row.title == race.session ? .red : .primary)
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
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeading(label: "FULL WEEKEND", trailing: race.isStale(at: entry.date) ? "缓存过期" : "F1", warning: race.isStale(at: entry.date))
            Text(race.meeting).font(.title3.bold()).lineLimit(2)
            Text(race.location ?? "Formula 1").font(.caption2).foregroundStyle(.secondary)
            ForEach(Array((race.sessions ?? []).prefix(6))) { row in
                VStack(spacing: 3) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(row.start == race.start ? .red : Color.primary.opacity(0.15)).frame(width: 3, height: 27)
                    Text(row.title).font(.subheadline.bold())
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(row.start, format: .dateTime.month().day().weekday(.abbreviated)).font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(row.start, style: .time).font(.caption.bold().monospacedDigit())
                    }
                }
                if row.id != race.sessions?.last?.id { Divider() }
                }
            }
            Spacer(minLength: 0)
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
            case .accessoryInline:
                Text("\(status(timing)) · \(timing.lap) · \(timing.drivers.first?.name ?? timing.session)")
            case .accessoryCircular:
                VStack(spacing: 2) { Image(systemName: "flag.checkered"); Text(timing.isStale(at: entry.date) ? "过期" : timing.lap).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7) }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(timing.session).bold(); Spacer(); Text(timing.lap) }.font(.caption)
                    Text("\(status(timing)) · \(timing.drivers.first?.name ?? timing.meeting)").font(.caption2).lineLimit(1)
                }
            }
        } else { WidgetEmpty(title: "F1 实时计时", icon: "antenna.radiowaves.left.and.right") }
    }
    private func status(_ timing: RaceTimingSnapshot) -> String { timing.isStale(at: entry.date) ? "数据过期" : timing.status }
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
                Text("PITPULSE").font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundStyle(.red)
                Text(timing.session.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                Text(timing.lap).font(.title2.bold().monospacedDigit())
                Text(status(timing)).font(.system(size: 9, weight: .semibold)).foregroundStyle(timing.isStale(at: entry.date) ? .orange : .red)
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
                        .foregroundStyle(.red).cornerRadius(2)
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
            if !compact { Text(driver.tire ?? "—").font(.system(size: 9, weight: .bold)).foregroundStyle(.red).frame(width: 16) }
        }.font(.system(size: compact ? 10 : 11))
    }
}


#if DEBUG
/// Uses the exact extension renderers; no separate mock layouts or fabricated data.
struct WidgetPreviewGallery: View {
    @Environment(\.colorScheme) private var systemScheme
    @State private var kind = 0
    @State private var size = 0
    @State private var theme = 0
    @State private var entry = RaceWeekendEntry(date: .now, snapshot: RaceWidgetCache.read(), timing: RaceWidgetCache.readTiming())
    private var family: WidgetFamily { size == 0 ? .systemSmall : size == 1 ? .systemMedium : .systemLarge }
    private var scheme: ColorScheme { theme == 1 ? .light : theme == 2 ? .dark : systemScheme }
    private var frame: CGSize { size == 0 ? CGSize(width: 158, height: 158) : size == 1 ? CGSize(width: 338, height: 158) : CGSize(width: 338, height: 354) }
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Picker("内容", selection: $kind) { Text("下一场").tag(0); Text("周末赛程").tag(1); Text("Live 计时").tag(2) }.pickerStyle(.menu)
                Picker("尺寸", selection: $size) { Text("小尺寸").tag(0); Text("中尺寸").tag(1); Text("大尺寸").tag(2) }.pickerStyle(.menu)
                Picker("外观", selection: $theme) { Text("跟随系统").tag(0); Text("浅色").tag(1); Text("深色").tag(2) }.pickerStyle(.menu)
                Group {
                    switch kind {
                    case 1: WeekendScheduleWidgetView(entry: entry, previewFamily: family)
                    case 2: LiveTimingWidgetView(entry: entry, previewFamily: family)
                    default: NextRaceWidgetView(entry: entry, previewFamily: family)
                    }
                }.padding(16).frame(width: frame.width, height: frame.height)
                    .environment(\.colorScheme, scheme)
                    .background(scheme == .dark ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.1)))
                Text("与桌面组件共享同一份布局代码和 App Group 数据。这里可检查各尺寸；实际桌面渲染仍由 iOS WidgetKit 决定。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("刷新组件数据") { entry = RaceWeekendEntry(date: .now, snapshot: RaceWidgetCache.read(), timing: RaceWidgetCache.readTiming()) }
            }.padding(20)
        }.navigationTitle("组件预览").navigationBarTitleDisplayMode(.inline)
    }
}
#endif
