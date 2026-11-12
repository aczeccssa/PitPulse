import AppKit
import SwiftUI
import SharedData

// MARK: - Design tokens

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
