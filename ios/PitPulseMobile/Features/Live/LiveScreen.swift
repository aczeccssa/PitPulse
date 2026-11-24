import SharedComponents
import SharedData
import SwiftUI
import UIKit

struct LiveScreen: View {
    private static let tabletWideMinWidth: CGFloat = 890
    private static let tabletHorizontalInset: CGFloat = 14

    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var model: MobileModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var battleDraft: BattleDraft?
    @State private var selectedNumber: String?
    @State private var islandPreviewPresented = false
    @State private var raceControlPresented = false
    @State private var isLandscape = false
    @State private var interfaceOrientation: UIInterfaceOrientation = .unknown
    @State private var landscapeBattlePresented = false

    private enum TabletPanel: String {
        case benchmarks, raceControl, driver, battle
    }

    private enum PanelSnap: String {
        case top = "Top half"
        case full = "Full height"
        case bottom = "Bottom half"

        static func target(at y: CGFloat, height: CGFloat) -> Self {
            if y < height * 0.38 { return .top }
            if y > height * 0.62 { return .bottom }
            return .full
        }
    }

    @State private var topPanel: TabletPanel? = .benchmarks
    @State private var bottomPanel: TabletPanel? = .raceControl
    @State private var fullPanel: TabletPanel?
    @State private var compactPanel: TabletPanel?
    @GestureState private var panelDragY: CGFloat?
    @State private var compactComparisonHeight: CGFloat = 240

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var snapshot: LiveSnapshot { model.liveSnapshot }
    private var isSelectingBattleDrivers: Bool { battleDraft != nil }
    private var sessionUsesClock: Bool {
        if snapshot.sessionId != nil { return snapshot.prefersSessionClock }
        if model.series == .wec { return false }
        guard let planned = model.scheduledLiveSession else { return false }
        return [.fp1, .fp2, .fp3, .qualifying, .sprintQualifying].contains(planned.session.sessionType)
    }

    private struct BattleDraft {
        let rowOrder: [String]
        var selection: [String]
    }

    var body: some View {
        let tablet = isPad
        let usesAccessibilityText = typeSize.isAccessibilitySize
        let tabletWideMinWidth = Self.tabletWideMinWidth
        Group {
            if isPad || isLandscape {
                landscapeLayout
            } else {
                compactTiming
            }
        }
        .background(PulseStyle.background)
        .background {
            LiveRotationAccess { interfaceOrientation = $0 }
                .frame(width: 0, height: 0)
        }
        .statusBarHidden(isLandscape && !isPad)
        .onGeometryChange(for: Bool.self) { geometry in
            if tablet { return geometry.size.width >= tabletWideMinWidth && geometry.size.height >= 460 && !usesAccessibilityText }
            return geometry.size.width > geometry.size.height
        } action: { landscape in
            if isPad, landscape, let compactPanel, !visibleTabletPanels.contains(compactPanel) {
                snapTabletPanel(compactPanel, to: compactPanel == .driver || compactPanel == .raceControl ? .bottom : .top)
            }
            isLandscape = landscape
            if !isPad && !landscape {
                if landscapeBattlePresented { closeLandscapeBattle() }
                if selectedNumber != nil { raceControlPresented = false }
            }
        }
        .sheet(isPresented: portraitRaceControl) { raceControlSheet }
        .sheet(isPresented: $islandPreviewPresented) { islandPreview }
        .sheet(isPresented: portraitDriverDetail) {
            if let number = selectedNumber {
                LiveDriverDetail(number: number)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: model.series) { resetSessionUI() }
        .onChange(of: model.displayedLiveSessionKey) { previous, current in
            if previous != nil, current != nil { resetSessionUI() }
        }
        .onChange(of: snapshot.drivers.map(\.number)) { _, numbers in
            if snapshot.sourceStatus == .connected, !numbers.isEmpty {
                battleDraft?.selection.removeAll { !numbers.contains($0) }
            }
        }
        .task { model.autoStartLiveOnce() }
    }

    private var compactTiming: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sessionHeader
                timingStatus
                timingBoard(selecting: isSelectingBattleDrivers)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .safeAreaInset(edge: .top, spacing: 0) { liveHeader }
    }

    private var portraitRaceControl: Binding<Bool> {
        Binding(get: { !isLandscape && raceControlPresented }, set: {
            if !$0 && !isLandscape { raceControlPresented = false }
        })
    }

    private var portraitDriverDetail: Binding<Bool> {
        Binding(get: { !isPad && !isLandscape && selectedNumber != nil }, set: {
            if !isPad && !$0 && !isLandscape { selectedNumber = nil }
        })
    }

    private var selectedDriver: LiveDriver? {
        snapshot.drivers.first { $0.number == selectedNumber }
    }

    private var battlePair: [LiveDriver] {
        model.sortedDrivers.filter { model.islandBattleNumbers.contains($0.number) }
    }

    private var landscapeBodyExtensionEdge: Edge.Set {
        // The two horizontal insets can be equal. Rotation identifies the device-bottom side.
        if isPad { return [] }
        return switch interfaceOrientation {
        case .landscapeRight: layoutDirection == .leftToRight ? .trailing : .leading
        case .landscapeLeft: layoutDirection == .leftToRight ? .leading : .trailing
        default: []
        }
    }

    private var landscapeLayout: some View {
        let raceOverDriver = !isPad && raceControlPresented && selectedDriver != nil
        let presentsOverlay = raceOverDriver || (!isPad && landscapeBattlePresented)
        return ZStack {
            VStack(spacing: 4) {
                landscapeHeader
                    .padding(.horizontal, isPad ? Self.tabletHorizontalInset : 4)
                timingStatus
                    .padding(.horizontal, isPad ? Self.tabletHorizontalInset : 4)
                GeometryReader { layout in
                    let hasSidePanel = selectedDriver != nil || raceControlPresented
                    let hasTabletInspector = fullPanel != nil || topPanel != nil || bottomPanel != nil
                    let inspectorWidth = min(540, max(340, (layout.size.width - 12) * 0.42))
                    let timingWidth = hasTabletInspector ? max(0, layout.size.width - 12 - inspectorWidth) : layout.size.width
                    HStack(alignment: .top, spacing: isPad ? 12 : 8) {
                        if isPad {
                            ZStack(alignment: .topLeading) {
                                let compact = !isLandscape
                                    || layout.size.width < Self.tabletWideMinWidth - 2 * Self.tabletHorizontalInset
                                let showsTiming = !compact || compactPanel == nil
                                let showsInspector = compact ? compactPanel != nil : hasTabletInspector
                                tabletTimingPanel(width: compact ? layout.size.width : timingWidth)
                                    .frame(width: compact ? layout.size.width : timingWidth)
                                    .allowsHitTesting(showsTiming)
                                    .accessibilityHidden(!showsTiming)
                                if showsInspector {
                                    let inspectorOffset = (timingWidth + 12) * (layoutDirection == .leftToRight ? 1 : -1)
                                    tabletInspector(compact: compact)
                                        .frame(width: compact ? layout.size.width : inspectorWidth)
                                        .background(compact ? PulseStyle.background : .clear)
                                        .offset(x: compact ? 0 : inspectorOffset)
                                        .transition(.opacity)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else {
                            landscapeScrollPanel {
                                timingBoard(selecting: false)
                            }
                            .frame(width: hasSidePanel ? max(0, (layout.size.width - 8) * 0.5) : layout.size.width)
                            if let driver = selectedDriver {
                                LiveLandscapeDriverPanel(driver: driver, close: { selectedNumber = nil })
                            } else if raceControlPresented {
                                VStack(spacing: 6) {
                                    HStack {
                                        Text("Race Control").font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                                        Spacer()
                                        closePanelButton("Close race control") { raceControlPresented = false }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.top, 6)
                                    ScrollView { raceControl }
                                }
                                .frame(maxWidth: .infinity)
                                .liveLandscapePanel(WebDashboardStyle.homePanel)
                            }
                        }
                    }
                }
                .padding(.horizontal, isPad ? Self.tabletHorizontalInset : 4)
                .padding(landscapeBodyExtensionEdge, 20)
                .ignoresSafeArea(.container, edges: landscapeBodyExtensionEdge)
            }
            .padding(.bottom, 6)
            .animation(isPad && !reduceMotion ? .easeInOut(duration: 0.24) : nil, value: isLandscape)
            .animation(isPad && !isLandscape && !reduceMotion ? .easeInOut(duration: 0.20) : nil, value: compactPanel)
            .scaleEffect(presentsOverlay ? 0.96 : 1, anchor: .top)
            .offset(y: presentsOverlay ? -8 : 0)
            .allowsHitTesting(!presentsOverlay)
            .accessibilityHidden(presentsOverlay)

            if raceOverDriver {
                landscapeBackdrop { raceControlPresented = false }
                    .allowsHitTesting(!landscapeBattlePresented)
                landscapeSheet("Race Control", close: { raceControlPresented = false }, offersBattle: true) {
                    ScrollView { raceControl }
                }
                .scaleEffect(landscapeBattlePresented ? 0.97 : 1, anchor: .top)
                .offset(y: landscapeBattlePresented ? -6 : 0)
                .allowsHitTesting(!landscapeBattlePresented)
                .accessibilityHidden(landscapeBattlePresented)
                .transition(panelTransition)
            }

            if !isPad && landscapeBattlePresented {
                landscapeBackdrop(close: closeLandscapeBattle)
                landscapeSheet(isSelectingBattleDrivers ? "Select Drivers to Compare" : "Driver Comparison",
                               close: closeLandscapeBattle, offersBattle: false) {
                    if let draft = battleDraft {
                        VStack(alignment: .leading, spacing: 6) {
                            PulseNumber("\(draft.selection.count) of 2 selected").font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            landscapeScrollPanel { timingBoard(selecting: true) }
                        }
                    } else if let front = battlePair.first, let back = battlePair.dropFirst().first {
                        LiveBattleDashboard(front: front, back: back)
                    } else {
                        Button("Select drivers", action: beginBattleSelection)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .transition(panelTransition)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: raceOverDriver)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: landscapeBattlePresented)
    }

    private func tabletBattlePanel(expanded: Bool, handle: AnyView?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(isSelectingBattleDrivers ? "Select Drivers" : "Driver Comparison")
                    .liveTabletPanelTitle()
                Spacer(minLength: 4)
                if !isSelectingBattleDrivers, battlePair.count == 2 {
                    Button("Change drivers", systemImage: "person.2", action: beginBattleSelection)
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .frame(width: 38, height: 44)
                }
                handle
            }
            if let draft = battleDraft {
                tabletBattlePicker(draft)
            } else if let front = battlePair.first, let back = battlePair.dropFirst().first {
                if expanded {
                    GeometryReader { geometry in
                        let minimumHeight: CGFloat = 430
                        if geometry.size.height >= minimumHeight {
                            LiveTabletBattleMetrics(front: front, back: back, expanded: true,
                                                    availableHeight: geometry.size.height)
                        } else {
                            ScrollView {
                                LiveTabletBattleMetrics(front: front, back: back, expanded: true,
                                                        availableHeight: minimumHeight)
                                    .frame(height: minimumHeight)
                            }
                        }
                    }
                } else {
                    LiveTabletBattleMetrics(front: front, back: back)
                }
            } else {
                Button("Select drivers", action: beginBattleSelection)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .frame(maxHeight: expanded || isSelectingBattleDrivers ? .infinity : nil, alignment: .top)
        .liveLandscapePanel(WebDashboardStyle.homePanel)
    }

    private func tabletBattlePicker(_ draft: BattleDraft) -> some View {
        let drivers = Dictionary(model.sortedDrivers.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = draft.selection.compactMap { drivers[$0] }
        return VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 146), spacing: 6)], spacing: 4) {
                    ForEach(draft.rowOrder.compactMap { drivers[$0] }, id: \.number) { driver in
                        tabletBattleOption(driver, selected: draft.selection.contains(driver.number))
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(selected.count) of 2 selected").font(.subheadline.weight(.semibold))
                    if !selected.isEmpty {
                        Text(selected.map { $0.name ?? "#\($0.number)" }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button {
                    guard selected.count == 2 else { return }
                    model.setIslandBattle(selected.map(\.number))
                    battleDraft = nil
                } label: {
                    Label("Compare", systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(PulseStyle.red.opacity(selected.count == 2 ? 0.14 : 0.04), in: .rect(cornerRadius: 9))
                        .foregroundStyle(selected.count == 2 ? PulseStyle.red : Color.secondary)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compare Drivers")
                .disabled(selected.count != 2)
                .accessibilityIdentifier("live.battle.confirm")
            }
        }
    }

    private func tabletBattleOption(_ driver: LiveDriver, selected: Bool) -> some View {
        Button {
            selectBattleDriver(driver.number)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? PulseStyle.red : Color.secondary)
                    .accessibilityHidden(true)
                if !snapshot.isWec {
                    AssetImage(name: model.helmetAsset(for: driver))
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(driver.name ?? "#\(driver.number)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Car \(driver.number)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let position = driver.position ?? driver.classPosition {
                    PulseNumber("P\(position)").font(.caption.weight(.semibold).monospacedDigit())
                        .fixedSize()
                }
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 44)
            .background(selected ? PulseStyle.red.opacity(0.16) : WebDashboardStyle.homePanel, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("live.battle.driver.\(driver.number)")
    }

    private func tabletTimingPanel(width: CGFloat) -> some View {
        landscapeScrollPanel {
            timingBoard(selecting: false, detailed: width >= 510, wide: width >= 650, stackedSectors: width < 350)
        }
    }

    private var visibleTabletPanels: [TabletPanel] {
        if let fullPanel { return [fullPanel] }
        return [topPanel, bottomPanel].compactMap { $0 }
    }

    private func tabletInspector(compact: Bool) -> some View {
        GeometryReader { geometry in
            let panels = compact ? compactPanel.map { [$0] } ?? [] : visibleTabletPanels
            let expanded = panels.count == 1
            let splitHeight = max(0, geometry.size.height - 8)
            let contentSizedComparison = !expanded && panels.contains(.battle)
                && battlePair.count == 2 && !isSelectingBattleDrivers
            let comparisonHeight = min(compactComparisonHeight, max(0, splitHeight - 100))
            let topHeight = contentSizedComparison
                ? (panels.first == .battle ? comparisonHeight : splitHeight - comparisonHeight)
                : splitHeight / 2
            ZStack(alignment: .top) {
                ForEach(panels, id: \.self) { panel in
                    let isTop = panels.first == panel
                    let height = expanded ? geometry.size.height : isTop ? topHeight : splitHeight - topHeight
                    Group {
                        if contentSizedComparison && panel == .battle {
                            tabletPanel(panel, expanded: false, inspectorHeight: geometry.size.height)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                    compactComparisonHeight = $0
                                }
                        } else {
                            tabletPanel(panel, expanded: expanded, inspectorHeight: geometry.size.height, movable: !compact)
                        }
                    }
                    .frame(width: geometry.size.width, height: height, alignment: .top)
                    .clipped()
                    .offset(y: isTop ? 0 : topHeight + 8)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: panels)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: topHeight)
            .overlay {
                if let panelDragY {
                    let canSplit = topPanel != nil && bottomPanel != nil
                    let target = canSplit ? PanelSnap.target(at: panelDragY, height: geometry.size.height) : .full
                    tabletSnapPreview(target: target, canSplit: canSplit)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .coordinateSpace(name: "live.inspector")
    }

    @ViewBuilder
    private func tabletPanel(_ panel: TabletPanel, expanded: Bool, inspectorHeight: CGFloat, movable: Bool = true) -> some View {
        let handle = movable ? AnyView(tabletPanelHandle(panel, height: inspectorHeight)) : nil
        switch panel {
        case .benchmarks:
            LiveLapBenchmarks(handle: handle, expanded: expanded)
        case .raceControl:
            tabletRaceControl(handle: handle)
        case .driver:
            if let driver = selectedDriver {
                LiveLandscapeDriverPanel(driver: driver, isTablet: true, panelHandle: handle,
                                         close: { closeTabletPanel(.driver) })
            } else {
                VStack {
                    HStack {
                        Text("Driver").font(.headline)
                        Spacer()
                        handle
                    }
                    ContentUnavailableView("Select a driver", systemImage: "steeringwheel")
                }
                .padding(12)
                .liveLandscapePanel(WebDashboardStyle.homePanel)
            }
        case .battle:
            tabletBattlePanel(expanded: expanded, handle: handle)
        }
    }

    private func tabletPanelHandle(_ panel: TabletPanel, height: CGFloat) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 38)
            .contentShape(.rect)
            .onTapGesture {
                if fullPanel == panel { fullPanel = nil }
                else { snapTabletPanel(panel, to: .full) }
            }
            .highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("live.inspector"))
                .updating($panelDragY) { gesture, value, _ in value = gesture.location.y }
                .onEnded { gesture in
                    snapTabletPanel(panel, to: PanelSnap.target(at: gesture.location.y, height: height))
                })
            .accessibilityLabel("Move panel")
            .accessibilityHint("Drag to the top, middle, or bottom of the right column")
            .accessibilityAction(named: Text("Top half")) { snapTabletPanel(panel, to: .top) }
            .accessibilityAction(named: Text("Full height")) { snapTabletPanel(panel, to: .full) }
            .accessibilityAction(named: Text("Bottom half")) { snapTabletPanel(panel, to: .bottom) }
            .accessibilityIdentifier("live.panel.handle.\(panel.rawValue)")
    }

    private func tabletSnapPreview(target: PanelSnap, canSplit: Bool) -> some View {
        ZStack {
            if canSplit {
                VStack(spacing: 8) {
                    snapOutline(.top, active: target == .top)
                    snapOutline(.bottom, active: target == .bottom)
                }
            }
            if target == .full {
                snapOutline(.full, active: true)
            } else {
                Text(PanelSnap.full.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(6)
                    .background(WebDashboardStyle.homePanel, in: .capsule)
            }
        }
        .padding(3)
    }

    private func snapOutline(_ destination: PanelSnap, active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(PulseStyle.red.opacity(active ? 0.16 : 0.025))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(active ? PulseStyle.red : Color.secondary,
                                  style: StrokeStyle(lineWidth: active ? 2 : 1, dash: [6, 4]))
            }
            .overlay {
                Text(destination.rawValue)
                    .font(.caption.bold())
                    .padding(6)
                    .background(WebDashboardStyle.homePanel, in: .capsule)
            }
    }

    private func snapTabletPanel(_ panel: TabletPanel, to destination: PanelSnap) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            compactPanel = panel
            if destination == .full {
                fullPanel = panel
                return
            }
            let oldTop = topPanel
            let oldBottom = bottomPanel
            fullPanel = nil
            if destination == .top {
                topPanel = panel
                bottomPanel = oldBottom == panel ? oldTop : oldBottom
            } else {
                bottomPanel = panel
                topPanel = oldTop == panel ? oldBottom : oldTop
            }
        }
    }

    private func tabletPanelIsVisible(_ panel: TabletPanel) -> Bool {
        if !isLandscape { return compactPanel == panel }
        if let fullPanel { return fullPanel == panel }
        return topPanel == panel || bottomPanel == panel
    }

    private func closeTabletPanel(_ panel: TabletPanel) {
        if compactPanel == panel { compactPanel = nil }
        if fullPanel == panel { fullPanel = nil }
        if topPanel == panel { topPanel = nil }
        if bottomPanel == panel { bottomPanel = nil }
        if panel == .battle { closeLandscapeBattle() }
        if panel == .driver { selectedNumber = nil }
    }

    private func toggleTabletPanel(_ panel: TabletPanel, destination: PanelSnap) {
        if !isLandscape {
            compactPanel = compactPanel == panel ? nil : panel
            return
        }
        if tabletPanelIsVisible(panel) {
            if fullPanel == panel, topPanel == panel || bottomPanel == panel {
                fullPanel = nil
            } else {
                closeTabletPanel(panel)
            }
        } else {
            snapTabletPanel(panel, to: destination)
        }
    }

    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private func landscapeBackdrop(close: @escaping () -> Void) -> some View {
        Color.black.opacity(0.30)
            .ignoresSafeArea(.container)
            .onTapGesture(perform: close)
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    private func landscapeScrollPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(content: content)
            .liveLandscapePanel(WebDashboardStyle.homePanel)
    }

    private func landscapeSheet<Content: View>(_ title: String, close: @escaping () -> Void,
                                               offersBattle: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(title).font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if offersBattle {
                    battleButton
                } else if !isSelectingBattleDrivers, battlePair.count == 2 {
                    Button("Change drivers", action: beginBattleSelection)
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 32)
                }
                closePanelButton("Close " + title, close: close)
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liveLandscapePanel(PulseStyle.background)
        .contentShape(PulseStyle.cardShape)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 5)
    }

    private func closePanelButton(_ title: String, close: @escaping () -> Void) -> some View {
        Button(title, systemImage: "xmark", action: close)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .background(.primary.opacity(0.06), in: .circle)
    }

    private var landscapeHeader: some View {
        Group {
            if isPad {
                if isLandscape {
                    ViewThatFits(in: .horizontal) {
                        tabletLandscapeHeader(scrollWeather: false)
                        tabletLandscapeHeader(scrollWeather: true)
                    }
                    .padding(.bottom, 5)
                } else {
                    tabletCompactHeader
                }
            } else {
                HStack(spacing: 8) {
                    closeLiveButton
                    landscapeSeriesLogo(width: 49, height: 18)
                    landscapeMeetingTitle
                    Spacer(minLength: 0)
                    trackStatus
                    landscapeProgress
                    landscapeActions
                }
            }
        }
        .accessibilityIdentifier("live.landscape.header")
    }

    private var tabletCompactHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                closeLiveButton
                landscapeMeetingTitle
                Spacer(minLength: 0)
                trackStatus
                landscapeProgress
            }
            .containerCornerOffset(.leading, sizeToFit: true)
            HStack(spacing: 8) {
                if compactPanel != nil {
                    headerButton("Back to timing", icon: "list.bullet") { compactPanel = nil }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        landscapeActions
                        landscapeSeriesLogo(width: 54, height: 22)
                        if let weather = snapshot.weather { trackWeather(weather) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func tabletLandscapeHeader(scrollWeather: Bool) -> some View {
        HStack(spacing: 12) {
            closeLiveButton
            landscapeSeriesLogo(width: 98, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                landscapeMeetingTitle
                HStack(spacing: 7) {
                    Text(model.liveSessionName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    trackStatus.fixedSize()
                    landscapeProgress
                }
            }
            .frame(minWidth: 165, alignment: .leading)
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                landscapeActions
                if let weather = snapshot.weather {
                    if scrollWeather {
                        ScrollView(.horizontal) { trackWeather(weather) }
                            .scrollIndicators(.hidden)
                            .frame(maxWidth: 640)
                    } else {
                        trackWeather(weather)
                    }
                }
            }
        }
        .containerCornerOffset(.leading, sizeToFit: true)
    }

    @ViewBuilder
    private var closeLiveButton: some View {
        if let onClose {
            Button("Close Live", systemImage: "chevron.down", action: onClose)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption.bold())
                .frame(width: 28, height: 44)
        }
    }

    private func landscapeSeriesLogo(width: CGFloat, height: CGFloat) -> some View {
        MotorsportImages.image(named: MotorsportAssetName.seriesLogoName(isWec: model.series == .wec))
            .renderingMode(.template)
            .resizable().scaledToFit()
            .frame(width: width, height: height)
            .accessibilityLabel(model.series.title)
            .contextMenu {
                if model.availableLiveSeries.count > 1 {
                    ForEach(model.availableLiveSeries) { series in
                        Button(series.title) { model.selectLiveSeries(series) }
                    }
                }
            }
    }

    private var landscapeMeetingTitle: some View {
        HStack(spacing: 8) {
            if let country = model.liveCountryCode {
                FlagBadge(countryCode: country, width: isPad ? 23 : 20)
                    .accessibilityHidden(true)
            }
            Text(model.liveMeetingName)
                .font(isPad ? .headline.bold() : .subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var landscapeProgress: some View {
        LiveClockTimeline(snapshot: snapshot, scheduledSession: model.liveScheduleForDisplay) { progress in
            PulseNumber(progress ?? "—")
        }
        .font((isPad ? Font.caption : .subheadline).bold().monospacedDigit())
        .fixedSize()
        .accessibilityLabel(sessionUsesClock ? "Time remaining" : "Laps")
    }

    private var landscapeActions: some View {
        HStack(spacing: 8) {
            battleButton
            headerButton("Dynamic Island", icon: "capsule") { islandPreviewPresented = true }
            headerButton("Race Control", icon: "flag.checkered") {
                if isPad { toggleTabletPanel(.raceControl, destination: .bottom) }
                else { raceControlPresented.toggle() }
            }
            .accessibilityAddTraits((isPad ? tabletPanelIsVisible(.raceControl) : raceControlPresented) ? .isSelected : [])
            if isPad {
                headerButton("Best Lap Benchmarks", icon: "bolt") {
                    toggleTabletPanel(.benchmarks, destination: topPanel == .battle ? .bottom : .top)
                }
                .accessibilityAddTraits(tabletPanelIsVisible(.benchmarks) ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func trackWeather(_ weather: LiveWeather) -> some View {
        let rain = weather.rainfall.map { $0 ? "Rain" : "Dry" } ?? "—"
        return HStack(spacing: 11) {
            weatherReading("Air", icon: "thermometer.low", tint: .blue, value: weatherValue(weather.airTemp, unit: "°C"))
            weatherReading("Track", icon: "thermometer.high", tint: .orange, value: weatherValue(weather.trackTemp, unit: "°C"))
            weatherReading("Hum", icon: "humidity", tint: .cyan, value: weatherValue(weather.humidity, unit: "%"))
            weatherReading("Wind", icon: "wind", tint: .secondary, value: weatherValue(weather.windSpeed, unit: "m/s"))
            weatherReading("Press", icon: "gauge.with.dots.needle.50percent", tint: .purple, value: weatherValue(weather.pressure, unit: "hPa"))
            weatherReading("Rain", icon: weather.rainfall == true ? "cloud.rain" : "drop", tint: .secondary, value: rain)
        }
        .font(.caption2.monospacedDigit())
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(WebDashboardStyle.homePanel, in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(WebDashboardStyle.homeLine) }
        .accessibilityIdentifier("live.track.weather")
    }

    private func weatherReading(_ label: String, icon: String, tint: Color, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
    }

    private func weatherValue(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }

    private func closeLandscapeBattle() {
        landscapeBattlePresented = false
        battleDraft = nil
    }

    private var islandPreview: some View {
        let chooseDrivers: (() -> Void)? = model.sortedDrivers.count >= 2 ? { beginBattleSelection() } : nil
        return IslandModePreviewSheet(onChooseBattleDrivers: chooseDrivers)
            .environmentObject(model)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }

    private var liveHeader: some View {
        VStack(spacing: 0) {
            if let onClose {
                Button(action: onClose) {
                    Capsule()
                        .fill(.secondary.opacity(0.55))
                        .frame(width: 36, height: 5)
                        .frame(width: 80, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Live")
                .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { gesture in
                    if gesture.translation.height > 32,
                       gesture.translation.height > abs(gesture.translation.width) { onClose() }
                })
            }

            HStack(spacing: 8) {
                MotorsportImages.image(named: MotorsportAssetName.seriesLogoName(isWec: model.series == .wec))
                    .renderingMode(.template)
                    .resizable().scaledToFit()
                    .frame(maxWidth: 96, maxHeight: 26)
                    .accessibilityLabel(model.series.title)
                Text(model.liveEntries[model.series]?.sourceMode == .replay ? "Replay" : "LIVE")
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .liveFilledCapsule()
                    .contextMenu {
                        Button(model.isLiveRunning ? "Disconnect" : "Connect", systemImage: "antenna.radiowaves.left.and.right") {
                            model.toggleLive()
                        }
                    }
                Spacer(minLength: 0)
                battleButton
                headerButton("Dynamic Island", icon: "capsule") { islandPreviewPresented = true }
                headerButton("Race Control", icon: "flag.checkered") { raceControlPresented = true }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .background(PulseStyle.background)
    }

    private func headerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.primary.opacity(0.06), in: .circle)
        }
        .buttonStyle(PulsePressStyle())
        .accessibilityLabel(title)
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.liveSessionName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.availableLiveSeries.count > 1 {
                    LiveSeriesPicker(series: model.availableLiveSeries, selected: model.series) {
                        model.selectLiveSeries($0)
                    }
                }
            }

            HStack(spacing: 10) {
                if let countryCode = model.liveCountryCode {
                    FlagBadge(countryCode: countryCode, width: 25)
                        .accessibilityHidden(true)
                }
                Text(model.liveMeetingName)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
            }

            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    sessionProgress
                    Spacer(minLength: 0)
                    trackStatus
                }
                VStack(alignment: .leading, spacing: 10) {
                    sessionProgress
                    trackStatus
                }
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardPanel(WebDashboardStyle.homePanel)
        .padding(.top, 4)
    }

    private var sessionProgress: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sessionUsesClock ? "Time Remaining" : "Laps")
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            LiveClockTimeline(snapshot: snapshot, scheduledSession: model.liveScheduleForDisplay) { progress in
                PulseNumber(progress ?? "—")
            }
            .font(.title3.weight(.bold).monospacedDigit())
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private var trackStatus: some View {
        let condition = snapshot.trackCondition
        let color: Color = switch condition {
        case .clear: WebDashboardStyle.adaptive(dark: 0x68d6a1, light: 0x176640)
        case .red: PulseStyle.red
        case .unknown: .secondary
        default: WebDashboardStyle.adaptive(dark: 0xffcc66, light: 0x855400)
        }

        return HStack(spacing: 5) {
            Image(systemName: condition.systemName)
            if let code = condition.code { Text(code).font(.caption.bold()) }
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(condition.englishLabel)
    }

    private var raceControlSheet: some View {
        NavigationStack {
            ScrollView {
                raceControl
                    .dashboardPanel(WebDashboardStyle.homePanel)
                    .padding(16)
            }
            .background(PulseStyle.background)
            .navigationTitle("Race Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close race control", systemImage: "xmark") { raceControlPresented = false }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var battleButton: some View {
        let drivers = model.sortedDrivers
        let pair = battlePair
        let gap = IslandBattleSelection.gap(between: pair)

        return Button {
            if isPad {
                if tabletPanelIsVisible(.battle) {
                    closeTabletPanel(.battle)
                } else {
                    if pair.count < 2 { beginBattleSelection() }
                    if isLandscape {
                        snapTabletPanel(.battle, to: topPanel == .benchmarks ? .bottom : .top)
                    } else {
                        compactPanel = .battle
                    }
                }
            } else if isLandscape {
                if pair.count < 2 { beginBattleSelection() }
                landscapeBattlePresented = true
            } else if isSelectingBattleDrivers {
                battleDraft = nil
            } else {
                beginBattleSelection()
            }
        } label: {
            Group {
                if let battleDraft {
                    HStack(spacing: 4) {
                        PulseNumber("\(battleDraft.selection.count)/2").monospacedDigit()
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(PulseStyle.red)
                } else if pair.count == 2 {
                    battlePreview(pair, gap: gap)
                } else {
                    Text("VS").font(.subheadline.bold().italic())
                }
            }
            .frame(width: 68, height: 44)
            .background(.primary.opacity(0.06), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(PulsePressStyle())
        .disabled(drivers.count < 2 && !isSelectingBattleDrivers)
        .accessibilityLabel(isSelectingBattleDrivers ? "Cancel driver selection" : "Select Drivers to Compare")
        .accessibilityValue(battleDraft.map { "\($0.selection.count) of 2 drivers selected" }
                            ?? (pair.count == 2 ? "\(pair.map { $0.name ?? $0.number }.joined(separator: "、")), gap \(gap ?? "Unknown")" : ""))
        .accessibilityIdentifier("live.battle")
        .contextMenu {
            if pair.count == 2, !isSelectingBattleDrivers {
                Button("Clear comparison", systemImage: "xmark") { model.resetIslandBattle() }
            }
        }
    }

    private func battlePreview(_ pair: [LiveDriver], gap: String?) -> some View {
        HStack(spacing: -7) {
            ForEach(pair, id: \.number) { driver in
                Group {
                    if snapshot.isWec {
                        Text("#\(driver.number)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .minimumScaleFactor(0.7)
                    } else {
                        AssetImage(name: model.helmetAsset(for: driver))
                            .padding(2)
                    }
                }
                .frame(width: 29, height: 29)
                .background(PulseStyle.surface, in: .circle)
                .overlay { Circle().strokeBorder(WebDashboardStyle.homeLine) }
            }
        }
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) {
            PulseNumber(gap ?? "—")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .liveFilledCapsule()
        }
        .accessibilityHidden(true)
    }

    private func beginBattleSelection() {
        let drivers = model.sortedDrivers
        guard drivers.count >= 2 else { return }
        let order = drivers.map(\.number)
        battleDraft = BattleDraft(rowOrder: order, selection: model.islandBattleNumbers.filter { order.contains($0) })
        if isPad {
            if isLandscape {
                if !tabletPanelIsVisible(.battle) { snapTabletPanel(.battle, to: topPanel == .benchmarks ? .bottom : .top) }
            } else {
                compactPanel = .battle
            }
        } else if isLandscape {
            landscapeBattlePresented = true
        }
    }

    private func selectBattleDriver(_ number: String) {
        guard var draft = battleDraft else { return }
        let available = model.sortedDrivers.map(\.number)
        guard available.contains(number) else { return }
        let selection = IslandBattleSelection.toggled(number, in: draft.selection.filter { available.contains($0) })
        if !isPad, selection.count == 2, selection != draft.selection {
            model.setIslandBattle(selection)
            battleDraft = nil
        } else {
            draft.selection = selection
            battleDraft = draft
        }
    }

    private func resetSessionUI() {
        selectedNumber = nil
        raceControlPresented = false
        closeTabletPanel(.battle)
        closeTabletPanel(.driver)
    }

    @ViewBuilder
    private var timingStatus: some View {
        if snapshot.sourceStatus == .stale, !snapshot.drivers.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .accessibilityHidden(true)
                Text(snapshot.statusReason == "data_stale" ? "Timing delayed" : "Showing last received timing")
                if snapshot.statusReason == "connecting" || snapshot.statusReason == "reconnecting" {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timingBoard(selecting: Bool, detailed: Bool = false, wide: Bool = false, stackedSectors: Bool = false) -> some View {
        let drivers = model.sortedDrivers
        let rows = (selecting ? battleDraft : nil).map { draft in
            drivers.sorted {
                (draft.rowOrder.firstIndex(of: $0.number) ?? Int.max) < (draft.rowOrder.firstIndex(of: $1.number) ?? Int.max)
            }
        } ?? drivers
        let timingAvailable = snapshot.sourceStatus != .disconnected && !drivers.isEmpty
        let awaitingStart = model.isLiveRunning && model.series == .f1 && model.scheduledLiveSession != nil
            && snapshot.statusReason != "unauthorized" && snapshot.statusReason != "server_unavailable"
        return Group {
            if snapshot.statusReason == "connecting", drivers.isEmpty, !model.hasActiveLive {
                PulseSkeleton(rows: 6, label: "Loading live timing")
            } else if LiveIslandLogic.isFinished(snapshot.sessionStatus) {
                ContentUnavailableView("Session finished", systemImage: "flag.checkered")
            } else if !timingAvailable && awaitingStart {
                ContentUnavailableView("Waiting for session timing", systemImage: "flag.checkered",
                                       description: Text("Timing will appear automatically when the feed publishes it."))
            } else if !timingAvailable {
                refreshTimingButton
            } else if detailed {
                detailedTimingTable(rows, wide: wide)
            } else {
                let table = VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        if selecting { Color.clear.frame(width: 44, height: 1) }
                        Text("#")
                            .accessibilityLabel("Position")
                            .frame(width: 24)
                        Text("Driver").frame(maxWidth: .infinity, alignment: .leading)
                        if !stackedSectors {
                            HStack(spacing: 4) {
                                ForEach(1...3, id: \.self) { index in
                                    Text("S\(index)").frame(maxWidth: .infinity)
                                }
                            }
                            .frame(width: 126)
                        }
                        if !selecting { Text("Gap / Tire").frame(width: 64, alignment: .trailing) }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, isLandscape ? 7 : 12)
                    ForEach(rows, id: \.number) { driver in
                        Divider()
                        driverRow(driver, selecting: selecting, stackedSectors: stackedSectors)
                    }
                }
                .padding(.horizontal, isLandscape ? 9 : 14)
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: rows.map(\.number))
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: stackedSectors)
                if isLandscape || isPad {
                    table
                } else {
                    table.dashboardPanel(WebDashboardStyle.homePanel)
                }
            }
        }
        .pulseSwap(drivers.isEmpty || !timingAvailable)
    }

    private func detailedTimingTable(_ rows: [LiveDriver], wide: Bool) -> some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(rows, id: \.number) { driver in
                    tabletTimingRow(driver, wide: wide)
                    Divider()
                }
            } header: {
                detailedTimingColumns(wide: wide) {
                    Text("POS")
                    Text("DRIVER")
                    Text("GAP")
                    Text("INT")
                    Text("LAST")
                    Text("BEST")
                    Text("SECTORS")
                    Text("TYRE")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .background(WebDashboardStyle.homePanel)
                .overlay(alignment: .bottom) { Divider() }
                .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private func openTabletDriver(_ number: String) {
        selectedNumber = number
        compactPanel = .driver
        if isLandscape && !tabletPanelIsVisible(.driver) { snapTabletPanel(.driver, to: .bottom) }
    }

    private func tabletTimingRow(_ driver: LiveDriver, wide: Bool) -> some View {
        let selected = selectedNumber == driver.number
        let favorite = model.favoriteDriverID.map { model.driverID(for: driver) == $0 } ?? false
        return Button {
            openTabletDriver(driver.number)
        } label: {
            detailedTimingColumns(wide: wide) {
                VStack(spacing: 2) {
                    PulseNumber((driver.position ?? driver.classPosition).map(String.init) ?? "—")
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if favorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(PulseStyle.red)
                            .accessibilityLabel("Favorite driver")
                    }
                }
                HStack(spacing: 7) {
                    if !snapshot.isWec {
                        AssetImage(name: model.helmetAsset(for: driver))
                            .frame(width: 25, height: 25)
                            .accessibilityHidden(true)
                    }
                    Text(wide ? driver.name ?? "#\(driver.number)"
                         : "#\(driver.number) \(driver.name.map(MotorsportAssetName.abbreviation) ?? "")")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityLabel("Car \(driver.number), \(driver.name ?? "Unknown driver")")
                    LiveDriverTrackStatus(driver: driver)
                        .fixedSize(horizontal: true, vertical: false)
                }
                timingValue(driver.gap, label: "Gap")
                timingValue(driver.interval, label: "Interval")
                timingValue(driver.lastLap, label: "Last lap")
                timingValue(driver.bestLap, label: "Best lap")
                LiveSectorTimes(sectors: driver.sectors ?? [], showsSegments: true, compactSegments: true)
                HStack(spacing: 3) {
                    LiveTireBadge(driver: driver, size: 17)
                    PulseNumber(driver.tireAgeLaps.map(String.init) ?? "—")
                        .font(.caption2)
                }
            }
            .font(.caption.monospacedDigit())
            .frame(minHeight: 44)
            .background(PulseStyle.red.opacity(selected ? 0.14 : favorite ? 0.045 : 0), in: Rectangle())
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(PulseStyle.red).frame(width: 3).allowsHitTesting(false) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("live.driver.\(driver.number)")
    }

    private func timingValue(_ value: String?, label: String) -> some View {
        PulseNumber(value ?? "—")
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityLabel("\(label) \(value ?? "unavailable")")
    }

    private func detailedTimingColumns<Content: View>(wide: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: wide ? 10 : 6) {
            Group(subviews: content()) { columns in
                columns[0].frame(width: 30)
                columns[1].frame(maxWidth: .infinity, alignment: .leading)
                ForEach(2...5, id: \.self) { index in
                    columns[index].frame(width: wide ? 62 : 49, alignment: .trailing)
                }
                columns[6].frame(width: wide ? 150 : 104)
                columns[7].frame(width: 44)
            }
        }
        .padding(.horizontal, 10)
    }

    private var refreshTimingButton: some View {
        Button("Refresh Timing", systemImage: "arrow.clockwise", action: model.refreshLive)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("live.retry")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    private func driverRow(_ driver: LiveDriver, selecting: Bool, stackedSectors: Bool) -> some View {
        let isSelected = battleDraft?.selection.contains(driver.number) ?? false
        let teamID = LiveIslandLogic.teamAssetID(for: driver, isWec: snapshot.isWec)
        let position = driver.position ?? driver.classPosition
        let isFocusedDriver = isPad && isLandscape && !selecting && selectedNumber == driver.number
        let isFavorite = model.favoriteDriverID.map { model.driverID(for: driver) == $0 } ?? false
        let logo = teamID.flatMap {
            DashboardArt.image(named: MotorsportAssetName.name(kind: .teamLogo, id: $0, season: model.liveArtSeason),
                               traits: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light))
        }

        let gap = driver.gap ?? driver.interval
        let gapText = gap?.uppercased() == "LEADER" ? "+0.000" : gap ?? "—"
        return Button {
            if selecting {
                selectBattleDriver(driver.number)
            } else if isPad {
                openTabletDriver(driver.number)
            } else {
                if isLandscape, selectedNumber == nil { raceControlPresented = false }
                selectedNumber = driver.number
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    if selecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? PulseStyle.red : .secondary)
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                    }
                    PulseNumber(position.map(String.init) ?? "—")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 24)
                        .overlay(alignment: .bottom) {
                            if isFavorite {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(PulseStyle.red)
                                    .offset(y: 9)
                                    .accessibilityLabel("Favorite driver")
                            }
                        }
                    HStack(spacing: 5) {
                        if !snapshot.isWec {
                            AssetImage(name: model.helmetAsset(for: driver)).frame(width: 26, height: 25)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("#\(driver.number) \(driver.name.map(MotorsportAssetName.abbreviation) ?? "—")")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .accessibilityLabel("Car \(driver.number), \(driver.name ?? "Unknown driver")")
                            if let logo {
                                Image(uiImage: logo).resizable().scaledToFit()
                                    .frame(width: 28, height: 13, alignment: .leading)
                                    .accessibilityLabel(driver.team ?? "Team")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !stackedSectors {
                        LiveSectorTimes(sectors: driver.sectors ?? [], showsSegments: false)
                            .frame(width: 126)
                    }
                    if !selecting {
                        VStack(alignment: .trailing, spacing: 3) {
                            PulseNumber(gapText)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .accessibilityLabel(driver.gap == nil && driver.interval != nil ? "Interval \(gapText)" : "Gap to leader \(gapText)")
                            HStack(spacing: 4) {
                                LiveDriverTrackStatus(driver: driver)
                                LiveTireBadge(driver: driver)
                            }
                        }
                        .frame(width: 64, alignment: .trailing)
                    }
                }
                if stackedSectors {
                    LiveSectorTimes(sectors: driver.sectors ?? [], showsSegments: true)
                        .padding(.leading, 30)
                }
            }
            .padding(.vertical, stackedSectors ? 5 : 0)
            .frame(minHeight: isLandscape ? 44 : 54)
            .background {
                if isFocusedDriver || isFavorite {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(PulseStyle.red.opacity(isFocusedDriver ? 0.14 : 0.065))
                        .padding(.horizontal, -5)
                        .padding(.vertical, 2)
                }
            }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PulsePressStyle())
        .disabled(selecting && (battleDraft?.selection.count ?? 0) == 2 && !isSelected)
        .accessibilityAddTraits((selecting && isSelected) || isFocusedDriver ? .isSelected : [])
        .accessibilityIdentifier(selecting ? "live.battle.driver.\(driver.number)" : "live.driver.\(driver.number)")
    }

    private func tabletRaceControl(handle: AnyView?) -> some View {
        let messages = snapshot.raceControl ?? []
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "flag.checkered")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text("Race Control").liveTabletPanelTitle()
                }
                Spacer(minLength: 4)
                Text(messages.count, format: .number)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.09), in: .capsule)
                    .accessibilityLabel("\(messages.count) messages")
                handle
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            Divider()
            if messages.isEmpty {
                ContentUnavailableView("No Race Control Messages", systemImage: "flag")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            tabletRaceControlItem(message)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liveLandscapePanel(WebDashboardStyle.homePanel)
    }

    private func tabletRaceControlItem(_ message: LiveRaceControlMessage) -> some View {
        let isPitExitOpen = message.message?.localizedCaseInsensitiveContains("pit exit open") == true
        let flag = message.flag?.uppercased()
        let color = flagColor(isPitExitOpen ? "GREEN" : flag)
        let title = isPitExitOpen ? "Pit Exit Open"
            : flag == "CLEAR" ? "Green" : (message.flag ?? message.category ?? "Race Control").capitalized
        let detail = message.sector.map { "\(title) (Sec. \($0))" } ?? title
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: isPitExitOpen ? "circle.fill" : "flag.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(detail).font(.caption2.weight(.semibold)).foregroundStyle(color)
                Spacer(minLength: 4)
                if let time = message.utc.flatMap(RFC3339.parse) {
                    Text(time.formatted(date: .omitted, time: .standard))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            Text(message.message ?? "—").font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }

    private var raceControl: some View {
        let messages = snapshot.raceControl ?? []
        return Group {
            if messages.isEmpty {
                ContentUnavailableView("No Race Control Messages", systemImage: "flag")
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                        if index > 0 { Divider() }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Label(message.flag ?? message.category ?? "Race Control", systemImage: "flag.fill")
                                    .foregroundStyle(flagColor(message.flag))
                                Spacer(minLength: 4)
                                if let lap = message.lap { Text("L\(lap)") }
                                if let time = message.utc.flatMap(RFC3339.parse) {
                                    Text(time, style: .time)
                                }
                            }
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            Text(message.message ?? "—").font(.subheadline)
                        }
                        .padding(.vertical, 13)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func flagColor(_ flag: String?) -> Color {
        switch flag?.uppercased() {
        case "BLUE": .blue
        case "YELLOW", "DOUBLE YELLOW": WebDashboardStyle.adaptive(dark: 0xffcc66, light: 0x855400)
        case "GREEN", "CLEAR": WebDashboardStyle.adaptive(dark: 0x68d6a1, light: 0x176640)
        case "RED": PulseStyle.red
        default: .secondary
        }
    }
}

struct LiveClockTimeline<Content: View>: View {
    let snapshot: LiveSnapshot
    var scheduledSession: NextSession? = nil
    @ViewBuilder let content: (String?) -> Content

    var body: some View {
        let suspended = snapshot.sourceStatus != .disconnected && LiveIslandLogic.isSuspended(snapshot.sessionStatus)
        if suspended || snapshot.sourceStatus == .stale {
            content(snapshot.prefersSessionClock ? snapshot.sessionClockLabel() : snapshot.lapCount.map { _ in snapshot.lapLabel })
        } else if snapshot.sourceStatus == .connected, snapshot.sessionClockLabel() != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(snapshot.sessionClockLabel(at: context.date))
            }
        } else if let session = scheduledSession?.session, [.fp1, .fp2, .fp3].contains(session.sessionType) {
            let end = session.endTime ?? session.startTime.addingTimeInterval(3600)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = end.timeIntervalSince(context.date)
                content(remaining > 0 ? LiveSnapshot.formattedClock(Int(remaining.rounded(.up))) : nil)
            }
        } else {
            content(snapshot.sourceStatus == .connected && !snapshot.prefersSessionClock && snapshot.lapCount != nil ? snapshot.lapLabel : nil)
        }
    }
}
