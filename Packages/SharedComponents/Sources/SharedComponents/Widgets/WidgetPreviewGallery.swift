#if os(iOS) || os(macOS)
import SwiftUI
import Charts
import WidgetKit
import SharedData

#if DEBUG
/// Uses the extension renderers and real App Group data, never sample race data.
public struct WidgetPreviewGallery: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPage: Int? = 0
    @State private var showInstructions = false
    @State private var entry = RaceWeekendEntry(date: .now, snapshot: RaceWidgetCache.readUpcoming()?.nextSession(at: .now) ?? RaceWidgetCache.read()?.advancing(to: .now), timing: RaceWidgetCache.readTiming())
    @State private var standingsEntry = StandingsWidgetEntry(date: .now, snapshot: RaceWidgetCache.readStandings())
    @State private var favoriteDriverEntry = FavoriteDriverWidgetEntry(date: .now, snapshot: RaceWidgetCache.readFavoriteDriver())
    @State private var lastRaceEntry = LastRaceWidgetEntry(date: .now, snapshot: RaceWidgetCache.readLastRace())
    @State private var upcomingEntry = UpcomingWidgetEntry(date: .now, snapshot: RaceWidgetCache.readUpcoming()?.remaining(at: .now))

    public init() {
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

    public var body: some View {
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
        .background {
            #if os(iOS)
            Color(uiColor: .systemGroupedBackground)
            #else
            widgetBackground
            #endif
        }
        .navigationTitle("组件预览")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showInstructions = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("如何添加小组件")
            }
            ToolbarItem(placement: .primaryAction) {
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
        entry = RaceWeekendEntry(date: now, snapshot: RaceWidgetCache.readUpcoming()?.nextSession(at: now) ?? RaceWidgetCache.read()?.advancing(to: now), timing: RaceWidgetCache.readTiming())
        standingsEntry = StandingsWidgetEntry(date: now, snapshot: RaceWidgetCache.readStandings())
        favoriteDriverEntry = FavoriteDriverWidgetEntry(date: now, snapshot: RaceWidgetCache.readFavoriteDriver())
        lastRaceEntry = LastRaceWidgetEntry(date: now, snapshot: RaceWidgetCache.readLastRace())
        upcomingEntry = UpcomingWidgetEntry(date: now, snapshot: RaceWidgetCache.readUpcoming()?.remaining(at: now))
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
        .background(widgetBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
#endif
