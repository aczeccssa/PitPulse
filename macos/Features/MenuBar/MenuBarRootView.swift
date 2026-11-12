import AppKit
import SwiftUI
import SharedData

// MARK: - Design tokens

enum PitPulseTheme {
    static let accent = Color(red: 0.84, green: 0.13, blue: 0.16)
    static let accentSoft = accent.opacity(0.14)
    static let windowWidth: CGFloat = 540
    static let windowHeight: CGFloat = 740
    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 10
    static let cardSpacing: CGFloat = 10
    static let pagePadding: CGFloat = 16
}

/// Liquid Glass card used by every page, so the popup reads as one system.
struct GlassCard<Content: View>: View {
    var radius: CGFloat = PitPulseTheme.cardRadius
    var padding: CGFloat = 14
    @ViewBuilder let content: () -> Content

    init(radius: CGFloat = PitPulseTheme.cardRadius, padding: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
        self.radius = radius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct CardHeader: View {
    let title: String
    var actionTitle: String? = nil
    var actionSymbol: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionTitle)
                        if let actionSymbol {
                            Image(systemName: actionSymbol).font(.system(size: 9, weight: .bold))
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PitPulseTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let symbol: String
    var tint: Color = .secondary
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct StatusPill: View {
    let text: String
    var tint: Color = .secondary
    var showsDot = true

    var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                Circle().fill(tint).frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: Capsule())
    }
}

struct GlassIconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Drivers are always represented by a helmet. A portrait is never used as a
/// stand-in; drivers without a helmet asset get a neutral helmet glyph.
struct DriverHelmetAvatar: View {
    let driverID: String
    let name: String
    let season: Int
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let image = MotorsportAsset.f1HelmetImage(id: driverID, season: season) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "helmet.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.primary.opacity(0.06), in: Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Shared Liquid Glass segmented control used by secondary pages.
struct LiquidSegmented<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String

        var id: Value { value }
    }

    let items: [Item]
    @Binding var selection: Value
    var compact = false

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(items) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = item.value }
                    } label: {
                        Text(item.title)
                            .font(.system(size: compact ? 11 : 11.5, weight: .semibold))
                            .foregroundStyle(selection == item.value ? PitPulseTheme.accent : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, compact ? 4 : 6)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        selection == item.value
                            ? .regular.tint(PitPulseTheme.accent.opacity(0.18)).interactive()
                            : .regular.interactive(),
                        in: Capsule()
                    )
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selection == item.value ? .isSelected : [])
                }
            }
        }
    }
}

struct EmptyStateCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        GlassCard {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }
}

// MARK: - Root

struct MenuBarRootView: View {
    enum Section: String, CaseIterable, Identifiable {
        case next
        case calendar
        case results
        case standings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .next: "比赛"
            case .calendar: "赛历"
            case .results: "成绩"
            case .standings: "积分"
            }
        }

        var refreshTarget: ManualRefreshTarget {
            switch self {
            case .next, .calendar: .calendar
            case .results: .results
            case .standings: .standings
            }
        }

        var symbol: String {
            switch self {
            case .next: "house"
            case .calendar: "calendar"
            case .results: "trophy"
            case .standings: "person.3"
            }
        }

        var selectedSymbol: String {
            switch self {
            case .next: "house.fill"
            case .calendar: "calendar"
            case .results: "trophy.fill"
            case .standings: "person.3.fill"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liveStore: LiveStore
    @EnvironmentObject private var liveIsland: LiveIslandController
    @Environment(\.openSettings) private var openSettings
    @State private var section: Section = .next
    @Namespace private var switcherNamespace

    var body: some View {
        VStack(spacing: 0) {
            header
            primarySwitcher
            Divider().opacity(0.5)
            content
            liveStrip
            Divider().opacity(0.5)
            footer
        }
        .frame(width: PitPulseTheme.windowWidth, height: PitPulseTheme.windowHeight)
        .onAppear {
            model.popupDidAppear()
        }
        .onDisappear {
            model.popupDidDisappear()
        }
        .onChange(of: section) { _, section in model.menuSectionDidChange(target: section.refreshTarget) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("PitPulseMenuBar")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 18)
                .accessibilityHidden(true)

            Text("PitPulse")
                .font(.system(size: 15, weight: .semibold))

            if liveStore.snapshot.sourceMode == .replay {
                Text("回放")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .glassEffect(.regular.tint(.orange.opacity(0.16)), in: Capsule())
            }

            Spacer(minLength: 8)

            if model.isRefreshing {
                ProgressView().controlSize(.mini)
            } else if let date = model.lastSuccessfulLoadAt {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// iOS-style Liquid Glass tab bar: one continuous glass capsule with a
    /// tinted lens that slides between the icon-only items.
    private var primarySwitcher: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Section.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { section = item }
                    } label: {
                        Image(systemName: section == item ? item.selectedSymbol : item.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(section == item ? PitPulseTheme.accent : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background {
                                if section == item {
                                    Capsule()
                                        .fill(PitPulseTheme.accent.opacity(0.15))
                                        .overlay {
                                            Capsule().strokeBorder(PitPulseTheme.accent.opacity(0.22), lineWidth: 1)
                                        }
                                        .matchedGeometryEffect(id: "liquidSwitcher", in: switcherNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(item.title)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(section == item ? "已选中" : "")
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                    .accessibilityIdentifier("menuBar.section.\(item.rawValue)")
                }
            }
            .padding(5)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch section {
            case .next:
                NextMeetingCard()
            case .calendar:
                CalendarView()
            case .results:
                SessionResultsView(model: model)
            case .standings:
                StandingsView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var liveStrip: some View {
        let snapshot = liveStore.snapshot
        if !snapshot.drivers.isEmpty, snapshot.sourceStatus == .connected {
            LiveStrip(
                snapshot: snapshot,
                favorite: liveFavorite,
                isVisible: liveIsland.isVisible,
                expand: {
                    if !liveIsland.isVisible { liveIsland.toggleManually() }
                }
            )
            .padding(.horizontal, PitPulseTheme.pagePadding)
            .padding(.bottom, 8)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                liveIsland.toggleManually()
            } label: {
                Image(systemName: liveIsland.isVisible ? "eye.slash" : "eye")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(liveIsland.isVisible ? "隐藏 Live Island" : "显示 Live Island")
            .accessibilityLabel(liveIsland.isVisible ? "隐藏 Live Island" : "显示 Live Island")
            .accessibilityIdentifier("menuBar.liveIsland")

            Spacer(minLength: 0)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 8) {
                    footerButton(symbol: AppSymbol.refresh.resolvedSystemName(), label: "刷新") {
                        model.refreshCurrentPage(target: section.refreshTarget)
                    }
                    .disabled(model.isRefreshing)
                    .opacity(model.isRefreshing ? 0.45 : 1)

                    footerButton(symbol: AppSymbol.settings.resolvedSystemName(), label: "设置") {
                        NSApp.keyWindow?.orderOut(nil)
                        NSApp.activate()
                        openSettings()
                    }
                    .accessibilityIdentifier("menuBar.settings")

                    footerButton(symbol: "power", label: "退出 PitPulse", prominent: true) {
                        NSApp.terminate(nil)
                    }
                    .accessibilityIdentifier("menuBar.quit")
                }
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.vertical, 12)
    }

    private func footerButton(
        symbol: String,
        label: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .frame(width: 22, height: 22)
                .padding(.horizontal, 8)
                .padding(.vertical, 9)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            prominent
                ? .regular.tint(PitPulseTheme.accent).interactive()
                : .regular.interactive(),
            in: Capsule()
        )
        .help(label)
        .accessibilityLabel(label)
    }

    private var liveFavorite: LiveDriver? {
        guard let favoriteID = model.favoriteDriverId(for: model.liveSeries) else { return nil }
        return LiveIslandLogic.matchedDriver(
            favoriteId: favoriteID,
            favorites: model.favoriteDrivers,
            drivers: liveStore.snapshot.drivers
        )
    }
}

// MARK: - Live strip

private struct LiveStrip: View {
    let snapshot: LiveSnapshot
    let favorite: LiveDriver?
    let isVisible: Bool
    let expand: () -> Void

    private var driver: LiveDriver? {
        favorite ?? snapshot.drivers.first
    }

    var body: some View {
        Button(action: expand) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(PitPulseTheme.accent).frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(PitPulseTheme.accent)
                }
                Text(snapshot.meetingName ?? snapshot.sessionName ?? "实时会话")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(snapshot.lapLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                if let driver {
                    Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow)
                    Text(driver.name ?? "#\(driver.number)")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(driver.classLabel ?? "P\(driver.position.map(String.init) ?? "—")")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    if let gap = driver.gap {
                        Text(gap)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(PitPulseTheme.accent.opacity(0.10)).interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("展开 Live Island")
        .accessibilityLabel("展开 Live Island，\(snapshot.meetingName ?? "实时会话")")
    }
}
