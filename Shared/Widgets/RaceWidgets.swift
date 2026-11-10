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
        .description("小尺寸聚焦最近两场，中尺寸展开周末时间轴，大尺寸显示完整场次安排。")
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

    private var page: Int { min(max(selectedPage ?? 0, 0), 8) }
    private var kind: Int { page / 3 }
    private var scheme: ColorScheme { systemScheme }
    private let titles = ["下一场 · Formula 1", "比赛周末 · Formula 1", "实时计时 · Formula 1"]
    private let descriptions = [
        "开赛倒计时、赛事信息与即将到来的比赛周末。",
        "从最近场次到完整周末，按你的桌面空间选择。",
        "排名、圈数与车手差距；回放和过期数据始终明确标记。"
    ]
    private let sizes = ["小尺寸", "中尺寸", "大尺寸"]

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text(titles[kind]).font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(descriptions[kind]).font(.subheadline)
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(sizes[page % 3]).font(.caption.weight(.medium)).foregroundStyle(.secondary)
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
                        ForEach(0..<9) { index in
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
                .accessibilityValue("第 \(page + 1) 页，共 9 页")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: select(min(page + 1, 8))
                    case .decrement: select(max(page - 1, 0))
                    @unknown default: break
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(0..<9) { index in
                    Button { select(index) } label: {
                        Circle().fill(index == page ? Color.primary : Color.secondary.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .frame(width: 14, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(titles[index / 3])，\(sizes[index % 3])")
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
        entry = RaceWeekendEntry(date: .now, snapshot: RaceWidgetCache.read(), timing: RaceWidgetCache.readTiming())
    }

    private func previewSize(_ size: Int) -> CGSize {
        size == 0 ? CGSize(width: 158, height: 158)
            : size == 1 ? CGSize(width: 338, height: 158) : CGSize(width: 338, height: 354)
    }

    private func preview(index: Int) -> some View {
        let size = index % 3
        let family: WidgetFamily = size == 0 ? .systemSmall : size == 1 ? .systemMedium : .systemLarge
        let native = previewSize(size)
        return Group {
            switch index / 3 {
            case 1: WeekendScheduleWidgetView(entry: entry, previewFamily: family)
            case 2: LiveTimingWidgetView(entry: entry, previewFamily: family)
            default: NextRaceWidgetView(entry: entry, previewFamily: family)
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
        .accessibilityLabel("\(titles[index / 3])，\(sizes[size])预览")
    }
}
#endif
