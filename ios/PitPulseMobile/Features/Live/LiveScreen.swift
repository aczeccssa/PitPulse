import SharedComponents
import SharedData
import SwiftUI
import UIKit

struct LiveScreen: View {
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var model: MobileModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var battleDraft: BattleDraft?
    @State private var selectedNumber: String?
    @State private var islandPreviewPresented = false
    @State private var raceControlPresented = false
    @State private var isLandscape = false
    @State private var interfaceOrientation: UIInterfaceOrientation = .unknown
    @State private var landscapeBattlePresented = false

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
        Group {
            if isLandscape {
                landscapeLayout
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        sessionHeader
                        timingBoard(selecting: isSelectingBattleDrivers)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .safeAreaInset(edge: .top, spacing: 0) { liveHeader }
            }
        }
        .background(PulseStyle.background)
        .background {
            LiveRotationAccess { interfaceOrientation = $0 }
                .frame(width: 0, height: 0)
        }
        .statusBarHidden(isLandscape)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { landscape in
            isLandscape = landscape
            if !landscape {
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

    private var portraitRaceControl: Binding<Bool> {
        Binding(get: { !isLandscape && raceControlPresented }, set: {
            if !$0 && !isLandscape { raceControlPresented = false }
        })
    }

    private var portraitDriverDetail: Binding<Bool> {
        Binding(get: { !isLandscape && selectedNumber != nil }, set: {
            if !$0 && !isLandscape { selectedNumber = nil }
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
        switch interfaceOrientation {
        case .landscapeRight: layoutDirection == .leftToRight ? .trailing : .leading
        case .landscapeLeft: layoutDirection == .leftToRight ? .leading : .trailing
        default: []
        }
    }

    private var landscapeLayout: some View {
        let raceOverDriver = raceControlPresented && selectedDriver != nil
        let presentsOverlay = raceOverDriver || landscapeBattlePresented
        return ZStack {
            VStack(spacing: 4) {
                landscapeHeader
                    .padding(.horizontal, 4)
                GeometryReader { layout in
                    let hasSidePanel = selectedDriver != nil || raceControlPresented
                    HStack(alignment: .top, spacing: 8) {
                        landscapeScrollPanel { timingBoard(selecting: false) }
                        .frame(width: hasSidePanel ? max(0, (layout.size.width - 8) / 2) : layout.size.width)
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
                .padding(.horizontal, 4)
                .padding(landscapeBodyExtensionEdge, 20)
                .ignoresSafeArea(.container, edges: landscapeBodyExtensionEdge)
            }
            .padding(.bottom, 6)
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

            if landscapeBattlePresented {
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
        HStack(spacing: 8) {
            if let onClose {
                Button("Close Live", systemImage: "chevron.down", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.caption.bold())
                    .frame(width: 28, height: 44)
            }
            MotorsportImages.image(named: MotorsportAssetName.seriesLogoName(isWec: model.series == .wec))
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 49, height: 18)
                .accessibilityLabel(model.series.title)
                .contextMenu {
                    if model.availableLiveSeries.count > 1 {
                        ForEach(model.availableLiveSeries) { series in
                            Button(series.title) { model.selectLiveSeries(series) }
                        }
                    }
                }
            if let country = model.liveCountryCode {
                FlagBadge(countryCode: country, width: 20)
                    .accessibilityHidden(true)
            }
            Text(model.liveMeetingName)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trackStatus
            LiveClockTimeline(snapshot: snapshot, scheduledSession: model.liveScheduleForDisplay) { progress in
                PulseNumber(progress ?? "—")
            }
            .font(.subheadline.bold().monospacedDigit())
            .fixedSize()
            .accessibilityLabel(sessionUsesClock ? "Time remaining" : "Laps")
            battleButton
            headerButton("Dynamic Island", icon: "capsule") { islandPreviewPresented = true }
            headerButton("Race Control", icon: "flag.checkered") { raceControlPresented.toggle() }
        }
        .accessibilityIdentifier("live.landscape.header")
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
            if isLandscape {
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
        if isLandscape { landscapeBattlePresented = true }
    }

    private func selectBattleDriver(_ number: String) {
        guard var draft = battleDraft else { return }
        let available = model.sortedDrivers.map(\.number)
        guard available.contains(number) else { return }
        let selection = IslandBattleSelection.toggled(number, in: draft.selection.filter { available.contains($0) })
        if selection.count == 2, selection != draft.selection {
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
        closeLandscapeBattle()
    }

    private func timingBoard(selecting: Bool) -> some View {
        let drivers = model.sortedDrivers
        let rows = (selecting ? battleDraft : nil).map { draft in
            drivers.sorted {
                (draft.rowOrder.firstIndex(of: $0.number) ?? Int.max) < (draft.rowOrder.firstIndex(of: $1.number) ?? Int.max)
            }
        } ?? drivers
        return Group {
            if snapshot.statusReason == "connecting", drivers.isEmpty, !model.hasActiveLive {
                PulseSkeleton(rows: 6, label: "Loading live timing")
            } else if LiveIslandLogic.isFinished(snapshot.sessionStatus) {
                ContentUnavailableView("Session finished", systemImage: "flag.checkered")
            } else if snapshot.sourceStatus != .connected {
                refreshTimingButton
            } else if drivers.isEmpty {
                refreshTimingButton
            } else {
                let table = VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        if selecting { Color.clear.frame(width: 44, height: 1) }
                        Text("#")
                            .accessibilityLabel("Position")
                            .frame(width: 18)
                        Text("Driver").frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 4) {
                            ForEach(1...3, id: \.self) { index in
                                Text("S\(index)").frame(maxWidth: .infinity)
                            }
                        }
                        .frame(width: 126)
                        if !selecting { Text("Gap / Tire").frame(width: 64, alignment: .trailing) }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, isLandscape ? 7 : 12)
                    ForEach(rows, id: \.number) { driver in
                        Divider()
                        driverRow(driver, selecting: selecting)
                    }
                }
                .padding(.horizontal, isLandscape ? 9 : 14)
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: rows.map(\.number))
                if isLandscape {
                    table
                } else {
                    table.dashboardPanel(WebDashboardStyle.homePanel)
                }
            }
        }
        .pulseSwap(drivers.isEmpty || snapshot.sourceStatus != .connected)
    }

    private var refreshTimingButton: some View {
        Button("Refresh Timing", systemImage: "arrow.clockwise", action: model.refreshLive)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("live.retry")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    private func driverRow(_ driver: LiveDriver, selecting: Bool) -> some View {
        let isSelected = battleDraft?.selection.contains(driver.number) ?? false
        let teamID = LiveIslandLogic.teamAssetID(for: driver, isWec: snapshot.isWec)
        let position = driver.position ?? driver.classPosition
        let isFavorite = model.favoriteDriverID.map { model.driverID(for: driver) == $0 } ?? false
        let logo = teamID.flatMap {
            DashboardArt.image(named: MotorsportAssetName.name(kind: .teamLogo, id: $0, season: model.season),
                               traits: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light))
        }

        let gap = driver.gap ?? driver.interval
        let gapText = gap?.uppercased() == "LEADER" ? "+0.000" : gap ?? "—"
        return Button {
            if selecting {
                selectBattleDriver(driver.number)
            } else {
                if isLandscape, selectedNumber == nil { raceControlPresented = false }
                selectedNumber = driver.number
            }
        } label: {
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
                    .frame(width: 18)
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

                LiveSectorTimes(sectors: driver.sectors ?? [], showsSegments: false)
                    .frame(width: 126)
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
            .frame(minHeight: isLandscape ? 44 : 54)
            .background {
                if isFavorite {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(PulseStyle.red.opacity(0.065))
                        .padding(.horizontal, -5)
                        .padding(.vertical, 2)
                }
            }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PulsePressStyle())
        .disabled(selecting && (battleDraft?.selection.count ?? 0) == 2 && !isSelected)
        .accessibilityAddTraits(selecting && isSelected ? .isSelected : [])
        .accessibilityIdentifier(selecting ? "live.battle.driver.\(driver.number)" : "live.driver.\(driver.number)")
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
        if snapshot.sourceStatus == .connected, snapshot.sessionClockLabel() != nil {
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
