import AppKit
import Combine
import NookApp
import OSLog
import SwiftUI
import SharedData

@MainActor
final class LiveIslandActions: ObservableObject {
    private enum Keys {
        static let tire = "liveIslandShowTire"
        static let energy = "liveIslandShowEnergy"
    }

    @Published var snapshot = LiveSnapshot.disconnected()
    @Published var presentation = "hidden"
    @Published var mode = "Telemetry"
    @Published var selectedNumber: String?
    @Published var showRadar = false
    @Published var messagePage = "Race Control"
    @Published var messageFilter = "all"
    @Published var messagesExpanded = false
    @Published var wecClass: String?
    @Published var showTire: Bool {
        didSet { defaults.set(showTire, forKey: Keys.tire) }
    }
    @Published var showEnergy: Bool {
        didSet { defaults.set(showEnergy, forKey: Keys.energy) }
    }
    let map = MapStore()
    let radio = RadioPlayer()
    var expand: (() -> Void)?
    var collapse: (() -> Void)?
    var hide: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showTire = defaults.object(forKey: Keys.tire) as? Bool ?? true
        showEnergy = defaults.object(forKey: Keys.energy) as? Bool ?? true
    }
}

@MainActor
final class LiveIslandController: ObservableObject {
    static let finishDisplayDuration: Duration = .seconds(30)

    @Published private(set) var isVisible = false
    @Published private(set) var lastKnownSnapshot: LiveSnapshot?

    let model: AppModel
    let nook: Nook<LiveIslandExpandedView, LiveIslandCompactLeading, LiveIslandCompactTrailing>

    private let logger = Logger(subsystem: "com.pitpulse.F1Companion", category: "LiveIsland")
    private let liveStore: LiveStore
    private let actions: LiveIslandActions
    private var cancellables = Set<AnyCancellable>()
    private var finishTask: Task<Void, Never>?
    private var finishSessionKey: String?
    private var activeSessionKey: String?
    private var automaticallyShown = false
    private var dismissedSessionKey: String?
    private var plannedSessionKey: String?
    private var transientPanels = 0
    private var clickMonitors: [Any] = []

    init(model: AppModel) {
        self.model = model
        self.liveStore = model.liveStore
        let actions = LiveIslandActions()
        self.actions = actions
        let nook = Nook(
            style: .standard,
            expanded: {
                LiveIslandExpandedView(model: model, actions: actions)
            },
            compactLeading: {
                LiveIslandCompactLeading(model: model, actions: actions)
            },
            compactTrailing: {
                LiveIslandCompactTrailing(model: model, actions: actions)
            }
        )
        self.nook = nook
        // Explicit hides must not wait for a pointer overlapping the menu bar.
        nook.hoverBehavior.remove(.keepVisible)
        actions.expand = { [weak nook] in Task { await nook?.expand(); NSApp.activate(); nook?.takeKeyboardFocus() } }

        nook.presentation = .auto
        nook.screenProvider = {
            #if DEBUG
            // Reproduce floating layout on existing hardware without changing system displays.
            if ProcessInfo.processInfo.environment["PITPULSE_ACCEPTANCE_SCREEN"] == "external",
               let screen = NSScreen.screens.first(where: {
                   guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                   return CGDisplayIsBuiltin(id.uint32Value) == 0 && $0.safeAreaInsets.top == 0
               }) {
                return screen
            }
            #endif
            return LiveIslandLogic.preferredScreen(in: NSScreen.screens, main: NSScreen.main) { screen in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                return CGDisplayIsBuiltin(id.uint32Value) != 0 && screen.safeAreaInsets.top > 0
            }
        }
        nook.onExpand = { [weak self] in
            self?.updateCollapseBehavior(expanded: true)
            self?.isVisible = true
            self?.configurePanel()
            self?.actions.presentation = "expanded"
            self?.diagnose("expanded")
        }
        nook.onCompact = { [weak self] in
            self?.stopClickMonitoring()
            self?.nook.staysExpandedOnHoverExit = false
            self?.actions.map.pause()
            self?.actions.radio.stop()
            self?.isVisible = true
            self?.configurePanel()
            self?.actions.presentation = "compact"
            self?.diagnose("compact")
        }
        nook.onHide = { [weak self] in
            guard let self else { return }
            self.isVisible = false
            self.stopClickMonitoring()
            self.actions.presentation = "hidden"
            self.actions.radio.stop()
            self.actions.map.pause()
            if self.automaticallyShown { self.dismissedSessionKey = self.activeSessionKey }
            self.automaticallyShown = false
            self.diagnose("hidden")
        }
        actions.collapse = { [weak nook] in Task { await nook?.compact() } }
        actions.hide = { [weak self] in self?.hide() }

        NotificationCenter.default.publisher(for: AppDelegate.reopenNotification)
            .sink { [weak self] _ in
                guard let self, !self.isVisible else { return }
                self.toggleManually()
            }
            .store(in: &cancellables)
        // Menus and popovers extend beyond the island's hover region.
        for (name, delta) in [(NSMenu.didBeginTrackingNotification, 1), (NSMenu.didEndTrackingNotification, -1),
                              (NSPopover.willShowNotification, 1), (NSPopover.didCloseNotification, -1)] {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.transientPanels = max(0, self.transientPanels + delta)
                    self.updateCollapseBehavior()
                }.store(in: &cancellables)
        }
        model.$notchCollapseOnMouseExit
            .sink { [weak self] automatic in self?.updateCollapseBehavior(automatic: automatic) }
            .store(in: &cancellables)
        model.$liveSeries
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                // Never carry the previous series' snapshot across a source switch.
                self.lastKnownSnapshot = nil
                self.activeSessionKey = nil
                self.actions.selectedNumber = nil
                self.actions.wecClass = nil
                self.actions.showRadar = false
                self.actions.radio.stop()
                self.actions.map.pause()
            }
            .store(in: &cancellables)
        liveStore.$snapshot
            .sink { [weak self] snapshot in self?.reconcile(snapshot: snapshot) }
            .store(in: &cancellables)
        model.$meetings
            .sink { [weak self] meetings in self?.reconcile(meetings: meetings) }
            .store(in: &cancellables)
        model.$notchAutoShowEnabled
            .sink { [weak self] enabled in self?.autoShowPreferenceChanged(enabled) }
            .store(in: &cancellables)
        model.$favoriteDriverId
            .merge(with: model.$favoriteWecDriverId)
            .sink { [weak self] id in
                guard let self else { return }
                let matched = LiveIslandLogic.matchedDriver(favoriteId: id, favorites: self.model.favoriteDrivers, drivers: self.snapshot.sourceStatus == .connected ? self.snapshot.drivers : []) != nil
                self.logger.notice("favoriteSelectionChanged selected=\(id != nil) matched=\(matched)")
            }
            .store(in: &cancellables)
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.reconcile()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.diagnose("screensChanged") }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification))
            .sink { [weak self] notification in
                guard let self, let window = notification.object as? NSWindow,
                      window === self.nook.window else { return }
                self.diagnose("panelFocusChanged")
            }
            .store(in: &cancellables)
        reconcile()
    }

    private func updateCollapseBehavior(automatic: Bool? = nil, expanded: Bool? = nil) {
        let automatic = automatic ?? model.notchCollapseOnMouseExit
        let expanded = expanded ?? (nook.state == .expanded)
        nook.staysExpandedOnHoverExit = expanded && (!automatic || transientPanels > 0)
        stopClickMonitoring()
        guard expanded, !automatic else { return }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor [weak self] in self?.collapseForOutsideClick() }
        }) { clickMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if MainActor.assumeIsolated({ self?.transientPanels == 0 }) {
                Task { @MainActor [weak self] in self?.collapseForOutsideClick() }
            }
            return event
        }) { clickMonitors.append(monitor) }
    }

    private func collapseForOutsideClick() {
        guard nook.state == .expanded, !model.notchCollapseOnMouseExit,
              transientPanels == 0, !nook.isHovering else { return }
        actions.collapse?()
    }

    private func stopClickMonitoring() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
    }

    isolated deinit {
        clickMonitors.forEach(NSEvent.removeMonitor)
    }

    var snapshot: LiveSnapshot {
        displayedSnapshot(for: liveStore.snapshot)
    }

    private func displayedSnapshot(for current: LiveSnapshot) -> LiveSnapshot {
        LiveIslandLogic.displayedSnapshot(current: current, lastKnown: lastKnownSnapshot, meetings: model.meetings, now: Date())
    }

    var currentPlannedSession: NextSession? {
        LiveIslandLogic.currentScheduledSession(in: model.meetings, now: Date())
    }

    func toggleManually() {
        diagnose("manualToggle")
        if isVisible {
            hide()
        } else {
            automaticallyShown = false
            dismissedSessionKey = nil
            model.ensureDriverStandingsLoaded()
            Task { await nook.expand(); NSApp.activate(); nook.takeKeyboardFocus() }
        }
    }

    func hide() {
        diagnose("hideRequested")
        dismissedSessionKey = activeSessionKey ?? currentPlannedSession?.session.id
        automaticallyShown = false
        finishTask?.cancel()
        finishTask = nil
        isVisible = false
        actions.presentation = "hidden"
        Task { await nook.hide() }
    }

    private func autoShowPreferenceChanged(_ enabled: Bool) {
        logger.notice("autoShow enabled=\(enabled, privacy: .public)")
        guard !enabled else {
            dismissedSessionKey = nil
            reconcile(autoShowEnabled: true)
            return
        }
        finishTask?.cancel()
        finishTask = nil
        if automaticallyShown { hide() }
    }

    private func reconcile(snapshot incomingSnapshot: LiveSnapshot? = nil, meetings incomingMeetings: [Meeting]? = nil, autoShowEnabled: Bool? = nil) {
        let current = incomingSnapshot ?? liveStore.snapshot
        let meetings = incomingMeetings ?? model.meetings
        let autoShowEnabled = autoShowEnabled ?? model.notchAutoShowEnabled
        if current.sourceStatus != .disconnected, current.sessionId != nil || current.sessionName != nil {
            lastKnownSnapshot = current
        }
        let displayed = LiveIslandLogic.displayedSnapshot(current: current, lastKnown: lastKnownSnapshot, meetings: meetings, now: Date())
        let planned = LiveIslandLogic.currentScheduledSession(in: meetings, now: Date())
        if let finishSessionKey, finishSessionKey != displayed.sessionId ?? displayed.sessionName {
            finishTask?.cancel()
            finishTask = nil
            self.finishSessionKey = nil
        }
        if actions.snapshot.sessionId != displayed.sessionId {
            actions.selectedNumber = nil
            actions.showRadar = false
            actions.messageFilter = "all"
            actions.radio.stop()
            actions.map.pause()
        }
        actions.snapshot = displayed
        if incomingSnapshot != nil {
            logger.info("contentUpdated version=\(displayed.stateVersion) status=\(displayed.sourceStatus.rawValue, privacy: .public) drivers=\(displayed.drivers.count) track=\(String(describing: displayed.trackCondition), privacy: .public) panelKey=\(self.nook.window?.isKeyWindow ?? false) appActive=\(NSApp.isActive)")
        }
        let key = displayed.sessionId ?? displayed.sessionName
        if displayed.sourceStatus == .connected, LiveIslandLogic.isStarted(displayed.sessionStatus) {
            plannedSessionKey = nil
            finishTask?.cancel()
            finishTask = nil
            finishSessionKey = nil
            let sessionChanged = activeSessionKey != key
            if sessionChanged { diagnose("sessionChanged") }
            activeSessionKey = key
            if LiveIslandLogic.shouldAutomaticallyShow(
                enabled: autoShowEnabled,
                dismissedSessionKey: dismissedSessionKey,
                sessionKey: key,
                sessionChanged: sessionChanged,
                isHidden: !isVisible
            ) {
                diagnose("automaticStarted")
                automaticallyShown = true
                isVisible = true
                model.ensureDriverStandingsLoaded()
                Task { await nook.compact() }
            }
            return
        }

        if LiveIslandLogic.isFinished(displayed.sessionStatus),
           let key = displayed.sessionId ?? displayed.sessionName {
            scheduleHide(for: key)
            return
        }

        if planned == nil, plannedSessionKey != nil, automaticallyShown {
            plannedSessionKey = nil
            hide()
        }
        if let planned, displayed.sourceStatus != .connected {
            activeSessionKey = planned.session.id
            plannedSessionKey = planned.session.id
            guard autoShowEnabled, !isVisible, dismissedSessionKey != planned.session.id else { return }
            automaticallyShown = true
            isVisible = true
            Task { await nook.compact() }
        }
    }

    // AppKit coordinates are logged separately from XCTest's accessibility coordinates.
    private func diagnose(_ event: String) {
        let window = nook.window
        let frame = window.map { NSStringFromRect($0.frame) } ?? "none"
        let screen = window?.screen
        let screenFrame = screen.map { NSStringFromRect($0.frame) } ?? "none"
        let scale = screen?.backingScaleFactor ?? 0
        let notch = (screen?.safeAreaInsets.top ?? 0) > 0
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        logger.notice("event=\(event, privacy: .public) observedState=\(String(describing: self.nook.state), privacy: .public) visible=\(self.isVisible, privacy: .public) automatic=\(self.automaticallyShown, privacy: .public) panelFrame=\(frame, privacy: .public) screenFrame=\(screenFrame, privacy: .public) scale=\(scale, privacy: .public) notch=\(notch, privacy: .public) panelVisible=\(window?.isVisible ?? false, privacy: .public) panelKey=\(window?.isKeyWindow ?? false, privacy: .public) appActive=\(NSApp.isActive, privacy: .public) frontmost=\(frontmost, privacy: .private)")
        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            logger.notice("screen id=\(id, privacy: .public) builtIn=\(CGDisplayIsBuiltin(id) != 0, privacy: .public) frame=\(NSStringFromRect(screen.frame), privacy: .public) visibleFrame=\(NSStringFromRect(screen.visibleFrame), privacy: .public) scale=\(screen.backingScaleFactor, privacy: .public) safeTop=\(screen.safeAreaInsets.top, privacy: .public)")
        }
    }

    private func configurePanel() {
        nook.configureWindow { window in
            window.hidesOnDeactivate = false
            (window as? NSPanel)?.becomesKeyOnlyIfNeeded = true
        }
    }

    private func scheduleHide(for key: String) {
        guard finishSessionKey != key else { return }
        finishTask?.cancel()
        finishSessionKey = key
        diagnose("finishedHideScheduled")
        finishTask = LiveIslandLogic.delayedHideTask(
            after: Self.finishDisplayDuration,
            shouldHide: { [weak self] in
                guard let self else { return false }
                return self.finishSessionKey == key
                    && (self.snapshot.sessionId ?? self.snapshot.sessionName) == key
                    && LiveIslandLogic.isFinished(self.snapshot.sessionStatus)
            },
            hide: { [weak self] in
                guard let self else { return }
                self.diagnose("finishedHideFired")
                self.finishSessionKey = nil
                self.automaticallyShown = false
                await self.nook.hide()
                self.diagnose("hideCompleted")
            }
        )
    }
}

struct LiveWaitingIndicator: View {
    let detail: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Image(systemName: "ellipsis")
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: 16, height: 16)
        .help(detail)
        .accessibilityLabel("等待实时数据")
        .accessibilityValue(detail)
    }
}

struct LiveIslandCompactLeading: View {
    @ObservedObject var model: AppModel
    @ObservedObject var actions: LiveIslandActions

    private var snapshot: LiveSnapshot { actions.snapshot }
    private var hasTiming: Bool { snapshot.sourceStatus == .connected }
    private var favorite: LiveDriver? {
        LiveIslandLogic.matchedDriver(
            favoriteId: model.favoriteDriverId(for: snapshot.isWec ? .wec : .f1),
            favorites: model.favoriteDrivers,
            drivers: hasTiming ? snapshot.drivers : []
        )
    }
    private var lapText: String {
        if snapshot.isWec, let laps = favorite?.lapCount { return "L\(laps)" }
        return snapshot.lapLabel
    }
    private var alertCode: String? {
        guard hasTiming else { return nil }
        return switch snapshot.trackCondition {
        case .clear, .unknown: nil
        case .yellow: "YF"
        case .fullCourseYellow: "FCY"
        case .safetyCar, .safetyCarEnding: "SC"
        case .virtualSafetyCar, .virtualSafetyCarEnding: "VSC"
        case .red: "RF"
        }
    }
    private var alertColor: Color {
        switch snapshot.trackCondition {
        case .yellow, .fullCourseYellow, .safetyCar: .yellow
        case .safetyCarEnding, .virtualSafetyCar, .virtualSafetyCarEnding: .orange
        case .red: .red
        default: .clear
        }
    }
    private var alertTextColor: Color {
        switch snapshot.trackCondition {
        case .yellow, .fullCourseYellow, .safetyCar: .black.opacity(0.8)
        default: .white
        }
    }

    var body: some View {
        Button { actions.expand?() } label: {
            HStack(spacing: 5) {
                if let logo = MotorsportAsset.seriesLogo(isWec: snapshot.isWec) {
                    Image(nsImage: logo)
                        .resizable().scaledToFit()
                        .frame(height: 11)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: AppSymbol.menuBar.resolvedSystemName())
                }
                Text(LiveIslandLogic.sessionLabel(snapshot.sessionType
                    ?? snapshot.sessionName
                    ?? model.currentIslandSession.map { $0.session.sessionType.displayName }
                    ?? model.nextSession.map { $0.session.sessionType.displayName }
                    ?? "PitPulse"))
                    .lineLimit(1)
                if hasTiming {
                    Text(lapText).monospacedDigit()
                }
                if let alertCode {
                    Text(alertCode)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(alertTextColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(alertColor, in: Capsule())
                        .accessibilityLabel(snapshot.trackCondition.label)
                }
            }
            .padding(.horizontal, alertCode == nil ? 0 : 8)
            .padding(.vertical, alertCode == nil ? 0 : 4)
            .background(alertCode == nil ? Color.clear : alertColor.opacity(0.18), in: Capsule())
            .overlay {
                if alertCode != nil {
                    Capsule().strokeBorder(alertColor.opacity(0.5), lineWidth: 0.5)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .accessibilityLabel("\(snapshot.isWec ? "WEC" : "F1")，\(snapshot.sessionType ?? snapshot.sessionName ?? "F1 Session")，\(snapshot.sessionStateLabel)，\(hasTiming ? "\(lapText)，\(snapshot.trackCondition.label)" : snapshot.statusLabel)")
        .accessibilityIdentifier("liveIsland.expand")
        .accessibilityHint("展开 Live Island")
        .environment(\.colorScheme, .dark)
    }
}

struct LiveIslandCompactTrailing: View {
    @ObservedObject var model: AppModel
    @ObservedObject var actions: LiveIslandActions

    private var favoriteID: String? {
        model.favoriteDriverId(for: actions.snapshot.isWec ? .wec : .f1)
    }

    private var favorite: LiveDriver? {
        LiveIslandLogic.matchedDriver(
            favoriteId: favoriteID,
            favorites: model.favoriteDrivers,
            drivers: actions.snapshot.sourceStatus == .connected ? actions.snapshot.drivers : []
        )
    }

    private var hasTiming: Bool { actions.snapshot.sourceStatus == .connected }

    private var statusText: String {
        if actions.snapshot.statusReason == "scheduled_session_waiting_for_live" {
            return "赛历安排；等待实时数据"
        }
        return actions.snapshot.statusLabel
    }

    var body: some View {
        Button { actions.expand?() } label: {
            HStack(spacing: 7) {
                if hasTiming {
                    if actions.snapshot.sourceMode == .replay {
                        Text("回放")
                            .font(.system(size: 9))
                    }
                    if let favorite {
                        LiveHelmetView(model: model, driver: favorite, size: 18, isWec: actions.snapshot.isWec)
                        Text("\(actions.snapshot.isWec ? "#\(favorite.number)" : MotorsportAsset.abbreviation(favorite.name ?? favorite.number)) P\(favorite.position.map(String.init) ?? "—")")
                            .monospacedDigit()
                    } else if favoriteID == nil {
                        Image(systemName: "star")
                            .help("选择关注车手")
                    } else {
                        Text("No selected")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .help("关注的车手不在本次会话中")
                            .accessibilityLabel("未选择，关注的车手不在本次会话中")
                    }
                } else {
                    if actions.snapshot.sourceMode == .replay {
                        Text("回放").font(.system(size: 9)).foregroundStyle(.orange)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if actions.snapshot.sessionId == nil, actions.snapshot.sessionName == nil,
                           let next = CalendarLogic.nextSession(in: model.meetings, now: context.date) {
                            Text(CalendarLogic.countdownText(until: next.session.startTime, now: context.date))
                                .monospacedDigit()
                        } else {
                            LiveWaitingIndicator(detail: statusText)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("展开 Live Island，选择或切换关注车手")
        .foregroundStyle(Color.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasTiming
            ? "\(actions.snapshot.statusLabel)，第 \((favorite?.lapCount ?? actions.snapshot.lapCount).map(String.init) ?? "—") 圈，关注车手 \(favorite?.name ?? "未选择")，名次 P\(favorite?.position.map(String.init) ?? "—")"
            : statusText)
        .environment(\.colorScheme, .dark)
    }
}

struct LiveIslandExpandedView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var actions: LiveIslandActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var map: MapStore
    @ObservedObject private var radio: RadioPlayer
    init(model: AppModel, actions: LiveIslandActions) {
        self.model = model
        self.actions = actions
        self.map = actions.map
        self.radio = actions.radio
    }
    private var mode: String { actions.mode }
    private var showRadar: Bool { actions.showRadar }
    /// The detail strip follows the clicked row, not the favourite: liking a
    /// car must never replace what is currently selected. When nothing is
    /// selected it falls back to a favourite that is actually in this session,
    /// otherwise it stays empty ("No selected").
    private var selectedDriver: LiveDriver? {
        if let number = actions.selectedNumber,
           let driver = snapshot.drivers.first(where: { $0.number == number }) {
            return driver
        }
        return favorite
    }
    private var meeting: Meeting? { LiveIslandLogic.meeting(for: snapshot, in: model.meetings, now: Date()) }

    private var snapshot: LiveSnapshot { actions.snapshot }
    private var hasTiming: Bool { snapshot.sourceStatus == .connected }
    // WEC publishes no mini-sector segments, so the sector columns stay compact
    // and the freed width carries a larger tire/energy readout.
    private var sectorWidth: CGFloat { snapshot.isWec ? 50 : 88 }
    private var wecTelemetryWidth: CGFloat { 106 }
    private var title: String {
        let components = [snapshot.meetingName, snapshot.sessionName ?? snapshot.sessionType].compactMap { $0 }
        if !components.isEmpty { return components.joined(separator: " · ") }
        return model.liveSeries == .wec ? "FIA WEC" : model.nextMeeting?.name ?? "PitPulse"
    }
    private var favoriteID: String? {
        model.favoriteDriverId(for: snapshot.isWec ? .wec : .f1)
    }

    private var favorite: LiveDriver? {
        LiveIslandLogic.matchedDriver(
            favoriteId: favoriteID,
            favorites: model.favoriteDrivers,
            drivers: hasTiming ? snapshot.drivers : []
        )
    }

    private var wecClasses: [(id: String, label: String, count: Int)] {
        var labels: [String: String] = [:]
        var counts: [String: Int] = [:]
        var order: [String] = []
        for driver in snapshot.drivers {
            guard let id = driver.classId, !id.isEmpty else { continue }
            if counts[id] == nil {
                order.append(id)
                labels[id] = (driver.className ?? id).uppercased()
            }
            counts[id, default: 0] += 1
        }
        let priority = ["HYPERCAR": 0, "LMP1": 1, "LMP2": 1, "LMGT3": 2]
        return order.sorted { (priority[$0] ?? 9, $0) < (priority[$1] ?? 9, $1) }
            .map { (id: $0, label: labels[$0] ?? $0, count: counts[$0] ?? 0) }
    }

    /// Best sector time per class, used to colour WEC's compact sector bars
    /// when the upstream feed provides no per-segment statuses.
    private var wecSectorBests: [String: [Double?]] {
        guard snapshot.isWec else { return [:] }
        var bests: [String: [Double?]] = [:]
        for driver in snapshot.drivers {
            let key = driver.classId ?? "ALL"
            var values = bests[key] ?? [nil, nil, nil]
            for index in 0..<min(3, driver.sectors?.count ?? 0) {
                guard let raw = driver.sectors?[index].value,
                      let seconds = LiveIslandLogic.sectorSeconds(raw) else { continue }
                values[index] = values[index].map { min($0, seconds) } ?? seconds
            }
            bests[key] = values
        }
        return bests
    }

    private var visibleDrivers: [LiveDriver] {
        guard snapshot.isWec, let selected = actions.wecClass,
              wecClasses.contains(where: { $0.id == selected }) else { return snapshot.drivers }
        return snapshot.drivers.filter { $0.classId == selected }
    }

    private func timingHeader(_ text: String, width: CGFloat) -> some View {
        Text(text).frame(width: width, alignment: .trailing)
    }

    private func timingValue(_ text: String?, label: String, width: CGFloat) -> some View {
        Text(text.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .lineLimit(1).frame(width: width, alignment: .trailing)
            .accessibilityLabel("\(label)，\(text.flatMap { $0.isEmpty ? nil : $0 } ?? "未提供")")
    }

    private var titleMenu: some View {
        Menu {
            ForEach(LiveSeries.allCases) { series in
                Button { model.setLiveSeries(series) } label: {
                    if model.liveSeries == series {
                        Label(series.title, systemImage: "checkmark")
                    } else {
                        Text(series.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title).font(.headline).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("切换 F1 / WEC 实时数据")
        .accessibilityLabel("\(title)，切换实时数据源")
        .accessibilityIdentifier("liveIsland.seriesMenu")
    }

    private var displayMenu: some View {
        Menu {
            Toggle("显示轮胎", isOn: $actions.showTire)
            if snapshot.isWec {
                Toggle("显示虚拟能量", isOn: $actions.showEnergy)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("选择显示的数据")
        .accessibilityLabel("选择显示的数据")
        .accessibilityIdentifier("liveIsland.columns")
    }

    private var classTabs: some View {
        HStack(spacing: 2) {
            classTab(id: nil, label: "全部", count: snapshot.drivers.count)
            ForEach(wecClasses, id: \.id) { item in
                classTab(id: item.id, label: item.label, count: item.count)
            }
        }
        .padding(2)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private func classTab(id: String?, label: String, count: Int) -> some View {
        let selected = actions.wecClass == id
        return Button { actions.wecClass = id } label: {
            HStack(spacing: 4) {
                Text(label)
                Text("\(count)").foregroundStyle(.secondary)
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(selected ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("显示 \(label) 组别")
        .accessibilityLabel("\(label)，\(count) 辆")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("liveIsland.class.\(id ?? "all")")
    }

    private var followControls: some View {
        HStack(spacing: 10) {
            if let favorite {
                LiveHelmetView(model: model, driver: favorite, size: 28, isWec: snapshot.isWec)
            }
            Menu {
                Button("不关注") { model.setFavoriteDriver(nil, series: snapshot.isWec ? .wec : .f1) }
                ForEach(LiveIslandLogic.favorites(for: snapshot.isWec ? .wec : .f1, in: model.favoriteDrivers)) { driver in
                    Button { model.setFavoriteDriver(driver.id, name: driver.name, series: snapshot.isWec ? .wec : .f1) } label: {
                        if favoriteID == driver.id {
                            Label(driver.name, systemImage: "checkmark")
                        } else {
                            Text(driver.name)
                        }
                    }
                }
            } label: {
                Image(systemName: favoriteID == nil ? "star" : "star.fill")
                    .foregroundStyle(favoriteID == nil ? Color.secondary : .yellow)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.favoriteDrivers.isEmpty)
            .help("选择或切换关注车手")
            .accessibilityLabel("选择关注车手")
            .accessibilityIdentifier("liveIsland.favoriteDriver")
            if let driver = favorite {
                Text("#\(driver.number) \(driver.name ?? "车手")")
                    .font(.caption.weight(.semibold)).lineLimit(1)
                Text("P\(driver.position.map(String.init) ?? "—") · \(driver.gap ?? "—")")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text("No selected")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
        }
    }

    private func modeButton(_ value: String, title: String, icon: String) -> some View {
        Button { actions.mode = value } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(mode == value ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
            .accessibilityLabel(title).accessibilityAddTraits(mode == value ? .isSelected : [])
            .accessibilityIdentifier("liveIsland.mode.\(value)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let logo = MotorsportAsset.seriesLogo(isWec: snapshot.isWec) {
                    Image(nsImage: logo)
                        .resizable().scaledToFit()
                        .frame(height: 15)
                        .accessibilityLabel(snapshot.isWec ? "WEC" : "F1")
                }
                titleMenu
                if snapshot.sourceMode == .replay { Text("回放").font(.caption2).foregroundStyle(.orange) }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    modeButton("Telemetry", title: "计时", icon: "chart.bar.xaxis")
                    modeButton("Live Map", title: "地图", icon: "map")
                }.padding(2).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                Button { actions.collapse?() } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).help("收起 Live Island").accessibilityLabel("收起 Live Island")
                    .accessibilityIdentifier("liveIsland.collapse").keyboardShortcut(.cancelAction)
                Button { actions.hide?() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("隐藏 Live Island").accessibilityLabel("隐藏 Live Island")
            }
            HStack(spacing: 10) {
                followControls
                LiveWeatherView(snapshot: snapshot)
                if hasTiming {
                    Text([snapshot.lapLabel, snapshot.remainingLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .help(snapshot.remainingLabel.map { "剩余 \($0)" } ?? "已完成圈数")
                    LiveTrackStatusBadge(snapshot: snapshot, compact: true)
                } else { LiveWaitingIndicator(detail: snapshot.statusLabel) }
                if mode == "Live Map" {
                    Button { actions.showRadar.toggle() } label: {
                        Image(systemName: "cloud.rain").foregroundStyle(showRadar ? Color.blue : Color.secondary)
                    }.buttonStyle(.borderless).help("历史降雨雷达")
                        .accessibilityLabel("历史降雨雷达").accessibilityValue(showRadar ? "开启" : "关闭")
                }
                displayMenu
            }
            if mode == "Telemetry" {
                if snapshot.isWec {
                    LiveWecCarView(
                        model: model,
                        driver: selectedDriver,
                        showTire: actions.showTire,
                        showEnergy: actions.showEnergy
                    )
                } else {
                    LiveF1CarView(model: model, driver: selectedDriver, snapshot: snapshot)
                }
            }
            if mode == "Telemetry", snapshot.isWec, hasTiming, !wecClasses.isEmpty {
                classTabs
            }
            ScrollView {

                VStack(alignment: .leading, spacing: 10) {

                    if mode == "Telemetry" {
                        if hasTiming {
                            let sectorBests = wecSectorBests
                            HStack(spacing: 8) {
                                HStack(spacing: 7) {
                                    Image(systemName: "star").frame(width: 17)
                                    Text("位置 / 车手")
                                }.frame(width: 224, alignment: .leading)
                                timingHeader("Gap", width: 58)
                                timingHeader("Interval", width: 58)
                                timingHeader("上一圈", width: 76)
                                timingHeader("最佳圈", width: 76)
                                ForEach(0..<3) { index in timingHeader("S\(index + 1)", width: sectorWidth) }
                                if snapshot.isWec {
                                    Text("轮胎 / 能量").frame(width: wecTelemetryWidth, alignment: .leading)
                                }
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            LazyVStack(spacing: 6) {
                                ForEach(visibleDrivers, id: \.number) { driver in
                                    let driverID = LiveIslandLogic.followableID(for: driver, favorites: model.favoriteDrivers, drivers: snapshot.drivers, isWec: snapshot.isWec)
                                    // Follow state is driver identity, not just a car number:
                                    // a liked driver who has left the car is not "followed" anymore.
                                    let followed = LiveIslandLogic.isFavoriteDriver(
                                        driver,
                                        favoriteId: favoriteID,
                                        favorites: model.favoriteDrivers
                                    )
                                    HStack(spacing: 0) {
                                            Button {
                                                if let driverID { model.setFavoriteDriver(followed ? nil : driverID, name: followed ? nil : driver.name, series: snapshot.isWec ? .wec : .f1) }
                                            } label: {
                                                Image(systemName: followed ? "star.fill" : "star").font(.caption).foregroundStyle(followed ? Color.yellow : Color.gray).frame(width: 25)
                                            }.buttonStyle(.plain).disabled(driverID == nil)
                                            .accessibilityLabel(followed ? "取消关注车手" : "关注车手")
                                            .accessibilityIdentifier("liveIsland.follow.\(driver.number)")
                                        Button {
                                            actions.selectedNumber = driver.number
                                        } label: {
                                            HStack(spacing: 8) {
                                                HStack(spacing: 7) {
                                                    Text(driver.position.map(String.init) ?? "—")
                                                        .font(.system(.body, design: .rounded).weight(.bold))
                                                        .frame(width: 24)
                                                        .accessibilityLabel("名次 P\(driver.position.map(String.init) ?? "未知")")
                                                    if snapshot.isWec {
                                                        LiveManufacturerLogo(driver: driver, season: model.selectedSeason)
                                                    } else {
                                                        LiveHelmetView(model: model, driver: driver, size: 32, isWec: false)
                                                    }
                                                    VStack(alignment: .leading, spacing: 3) {
                                                        Text(driver.name ?? "#\(driver.number)").font(.caption.weight(.semibold)).lineLimit(1)
                                                        HStack(spacing: 5) {
                                                            if !snapshot.isWec {
                                                                if actions.showTire, driver.tireLabel != nil {
                                                                    LiveTireInline(driver: driver)
                                                                }
                                                                if actions.showEnergy, driver.energyPercent != nil {
                                                                    LiveEnergyInline(percent: driver.energyPercent)
                                                                }
                                                            }
                                                            Text(driver.retired == true ? "已退赛" : driver.inPit == true ? "进站中" : driver.team ?? "—")
                                                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                                        }
                                                    }
                                                }.frame(width: 199, alignment: .leading)
                                                timingValue(driver.gap, label: "距领先车手", width: 58)
                                                timingValue(driver.interval, label: "距前车", width: 58)
                                                timingValue(driver.lastLap, label: "上一圈", width: 76)
                                                timingValue(driver.bestLap, label: "最佳圈", width: 76)
                                                ForEach(0..<3) { index in
                                                    let classBest = snapshot.isWec
                                                        ? (sectorBests[driver.classId ?? "ALL"]?[index] ?? nil)
                                                        : nil
                                                    LiveSectorView(
                                                        sector: driver.sectors.flatMap { index < $0.count ? $0[index] : nil },
                                                        index: index,
                                                        showsSegments: !snapshot.isWec,
                                                        referenceSeconds: classBest
                                                    )
                                                    .frame(width: sectorWidth)
                                                }
                                                if snapshot.isWec {
                                                    LiveWecTireEnergyCell(
                                                        driver: driver,
                                                        showTire: actions.showTire,
                                                        showEnergy: actions.showEnergy
                                                    )
                                                    .frame(width: wecTelemetryWidth)
                                                }
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 8)
                                            .background(followed ? Color.blue.opacity(0.22) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            if let driverID { Button(followed ? "取消关注" : "关注车手") { model.setFavoriteDriver(followed ? nil : driverID, name: followed ? nil : driver.name, series: snapshot.isWec ? .wec : .f1) } }
                                        }
                                        .help("点击查看车辆遥测，右键可关注车手")
                                        .accessibilityHint("激活后选择这名车手查看遥测")
                                        .accessibilityValue(followed ? "已关注" : "未关注")
                                        .accessibilityIdentifier("liveIsland.select.\(driver.number)")
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                            }

                        } else if model.liveSeries == .wec {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(snapshot.statusReason == "disabled"
                                    ? "WEC Live 未在服务端启用"
                                    : "当前没有正在进行的 WEC 会话")
                                    .font(.subheadline)
                                Text(snapshot.statusReason == "disabled"
                                    ? "在本地 environment.json 中设置 F1_COMPANION_WEC_LIVE_ENABLED=1 后重启服务端。"
                                    : "顶部可随时切回 F1。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        } else {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(model.plannedIslandSessionLabel(for: snapshot, now: context.date))
                                        .font(.subheadline)
                                    if let meeting = CalendarLogic.featuredMeeting(in: model.meetings, now: context.date) {
                                        Text(meeting.name).font(.headline)
                                        Text(meeting.location).font(.caption).foregroundStyle(.secondary)
                                        ForEach(meeting.sessions.sorted { $0.startTime < $1.startTime }) { session in
                                            HStack {
                                                Text(session.sessionType.displayName)
                                                Spacer()
                                                Text(session.startTime.formatted(.dateTime.weekday().hour().minute()))
                                                    .monospacedDigit()
                                            }
                                            .font(.caption)
                                            .padding(.vertical, 3)
                                        }
                                    }
                                }
                            }
                        }

                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        MapView(store: map, meeting: meeting, snapshot: snapshot, selected: selectedDriver?.number, radar: showRadar, active: mode == "Live Map" && actions.presentation == "expanded", now: context.date)
                            .frame(height: mode == "Live Map" ? (showRadar ? 210 : 250) : 0)
                            .opacity(mode == "Live Map" ? 1 : 0)
                            .allowsHitTesting(mode == "Live Map")
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if mode == "Live Map" {
                        if let error = map.error {
                            HStack(spacing: 8) {
                                Label("地图暂时不可用", systemImage: "exclamationmark.triangle").help(error)
                                Button("重试") { Task { map.release(); await map.load(model: model, meeting: meeting); map.onDriver = { actions.selectedNumber = $0 } } }
                                Spacer()
                            }.font(.caption2).foregroundStyle(.secondary)
                        }
                        if showRadar { RadarControls(model: model, map: map) }
                    }


                }
                .background(CalendarScrollAppearance())
            }
            Divider()
            LiveMessagesView(model: model, player: radio, snapshot: snapshot, selected: selectedDriver?.number, page: $actions.messagePage, filter: $actions.messageFilter, expanded: $actions.messagesExpanded)
        }
        .padding(16)
        .frame(width: 860)
        .frame(maxHeight: 490)
        .foregroundStyle(Color.white)
        .accessibilityElement(children: .contain)
        .onAppear(perform: model.ensureDriverStandingsLoaded)
        .task(id: "\(mode)-\(model.serverAddress)-\(meeting?.id ?? "none")-\(actions.presentation)") {
            guard mode == "Live Map", actions.presentation == "expanded" else {
                map.pause()
                return
            }
            await map.load(model: model, meeting: meeting)
            map.onDriver = { actions.selectedNumber = $0 }
        }
        .onChange(of: actions.presentation) { _, value in
            if value != "expanded" { radio.stop(); map.pause() }
            if value == "hidden" { map.pause() }
        }
        .onChange(of: model.serverAddress) { _, _ in radio.stop() }
        .onDisappear { radio.stop(); map.pause() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hasTiming)
        .environment(\.colorScheme, .dark)
    }
}

private struct LiveHelmetView: View {
    @ObservedObject var model: AppModel
    let driver: LiveDriver
    let size: CGFloat
    var isWec = false

    private var image: NSImage? {
        if isWec {
            guard let id = LiveIslandLogic.driverAssetID(for: driver) else { return nil }
            return MotorsportAsset.image(kind: .driverPhoto, id: id, season: model.selectedSeason)
        }
        guard let id = LiveIslandLogic.rosterID(for: driver, favorites: model.favoriteDrivers) else { return nil }
        return MotorsportAsset.f1DriverImage(id: id, season: model.selectedSeason)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text(MotorsportAsset.abbreviation(driver.name ?? driver.number))
                    .font(.system(size: size / 3, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct LiveTeamLogo: View {
    let driver: LiveDriver
    let season: Int
    var isWec = false
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let id = LiveIslandLogic.teamAssetID(for: driver, isWec: isWec),
               let image = MotorsportAsset.image(kind: .teamLogo, id: id, season: season) {
                Image(nsImage: image).resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct LiveManufacturerLogo: View {
    let driver: LiveDriver
    let season: Int
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let id = LiveIslandLogic.wecManufacturerAssetID(for: driver),
               let image = MotorsportAsset.image(kind: .teamLogo, id: id, season: season) {
                // Keep the 32pt row slot but draw the mark at 80% so it does
                // not crowd the driver name.
                Image(nsImage: image).resizable().scaledToFit().padding(size * 0.1)
            } else {
                Text(MotorsportAsset.abbreviation(driver.manufacturer ?? driver.team ?? driver.number))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct LiveF1CarView: View {
    @ObservedObject var model: AppModel
    let driver: LiveDriver?
    let snapshot: LiveSnapshot

    private var followed: Bool {
        guard let driver else { return false }
        return LiveIslandLogic.isFavoriteDriver(
            driver,
            favoriteId: model.favoriteDriverId(for: .f1),
            favorites: model.favoriteDrivers
        )
    }

    private var followID: String? {
        guard let driver else { return nil }
        return LiveIslandLogic.followableDriverID(
            for: driver,
            favorites: model.favoriteDrivers,
            drivers: snapshot.drivers
        )
    }

    private var detail: String {
        guard let driver else { return "" }
        return [driver.team, driver.tireLabel].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                if let driver {
                    LiveHelmetView(model: model, driver: driver, size: 30, isWec: false)
                    if let teamID = LiveIslandLogic.carSideAssetID(for: driver, isWec: false),
                       let image = MotorsportAsset.image(kind: .carSide, id: teamID, season: model.selectedSeason) {
                        Image(nsImage: image)
                            .resizable().scaledToFit()
                            .frame(width: 132, height: 32)
                    }
                    LiveTeamLogo(driver: driver, season: model.selectedSeason, isWec: false, size: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("#\(driver.number) \(driver.name ?? "车手")")
                                .font(.caption.weight(.semibold)).lineLimit(1)
                            if let position = driver.position {
                                Text("P\(position)")
                                    .font(.caption2.weight(.bold)).monospacedDigit()
                            }
                            if let gap = driver.gap, !gap.isEmpty {
                                Text(gap)
                                    .font(.caption2).monospacedDigit()
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                            Button {
                                guard let followID else { return }
                                model.setFavoriteDriver(
                                    followed ? nil : followID,
                                    name: followed ? nil : driver.name,
                                    series: .f1
                                )
                            } label: {
                                Image(systemName: followed ? "star.fill" : "star")
                                    .font(.caption2)
                                    .foregroundStyle(followed ? Color.yellow : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(followID == nil)
                            .help(followed ? "取消关注该车手" : "关注该车手")
                            .accessibilityLabel(followed ? "取消关注该车手" : "关注该车手")
                        }
                        Text(detail)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if let data = driver.telemetry,
                       snapshot.sourceMode == .replay || LiveFreshness.isFresh(data.receivedAt ?? data.utc, now: context.date) {
                        HStack(spacing: 10) {
                            metric("速度", data.speed, "km/h")
                            metric("RPM", data.rpm, "")
                            metric("挡位", data.gear, "")
                        }
                    }
                } else {
                    Text("No selected").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ label: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f", $0) + unit } ?? "—").monospacedDigit()
        }
        .font(.caption2)
    }
}

private struct LiveWecCarView: View {
    @ObservedObject var model: AppModel
    let driver: LiveDriver?
    let showTire: Bool
    let showEnergy: Bool

    private var detail: String {
        guard let driver else { return "" }
        return [driver.classLabel, driver.team].compactMap { $0 }.joined(separator: " · ")
    }

    private var followed: Bool {
        guard let driver else { return false }
        return LiveIslandLogic.isFavoriteDriver(
            driver,
            favoriteId: model.favoriteDriverId(for: .wec),
            favorites: model.favoriteDrivers
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            if let driver {
                LiveHelmetView(model: model, driver: driver, size: 30, isWec: true)
                if let carID = LiveIslandLogic.carSideAssetID(for: driver, isWec: true),
                   let image = MotorsportAsset.image(kind: .carSide, id: carID, season: model.selectedSeason) {
                    Image(nsImage: image)
                        .resizable().scaledToFit()
                        .frame(width: 120, height: 35)
                }
                LiveTeamLogo(driver: driver, season: model.selectedSeason, isWec: true, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("#\(driver.number) \(driver.name ?? "车手")")
                            .font(.caption.weight(.semibold)).lineLimit(1)
                        if let position = driver.position {
                            Text("P\(position)")
                                .font(.caption2.weight(.bold)).monospacedDigit()
                        }
                        if let gap = driver.gap, !gap.isEmpty {
                            Text(gap)
                                .font(.caption2).monospacedDigit()
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        Button {
                            model.setFavoriteDriver(
                                followed ? nil : "wec:\(driver.number)",
                                name: followed ? nil : driver.name,
                                series: .wec
                            )
                        } label: {
                            Image(systemName: followed ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(followed ? Color.yellow : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(followed ? "取消关注该车手" : "关注该车手")
                        .accessibilityLabel(followed ? "取消关注该车手" : "关注该车手")
                    }
                    Text(detail)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if showTire, driver.tireLabel != nil {
                    HStack(spacing: 4) {
                        Text("轮胎").foregroundStyle(.secondary)
                        LiveTireInline(driver: driver, fontSize: 11)
                    }
                    .font(.caption2)
                }
                if showEnergy, driver.energyPercent != nil {
                    HStack(spacing: 4) {
                        Text("能量").foregroundStyle(.secondary)
                        LiveEnergyInline(percent: driver.energyPercent)
                    }
                    .font(.caption2)
                }
            } else {
                Text("No selected").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LiveTireInline: View {
    let driver: LiveDriver
    var fontSize: CGFloat = 9

    private var color: Color {
        switch driver.tireCompound?.uppercased() {
        case "SOFT": .red
        case "MEDIUM": .yellow
        case "HARD": .white
        case "INTERMEDIATE", "INTER": .green
        case "WET": .blue
        default: .gray
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(driver.tireShortLabel ?? "—")
                .font(.system(size: fontSize, weight: .heavy))
                .foregroundStyle(color)
            if let age = driver.tireAgeLaps {
                Text("\(age)")
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .help(driver.tireLabel.map { "轮胎 \($0)" } ?? "轮胎未提供")
        .accessibilityLabel(driver.tireLabel.map { "轮胎 \($0)" } ?? "轮胎未提供")
    }
}

private struct LiveEnergyInline: View {
    let percent: Double?

    private var color: Color {
        guard let percent else { return .gray }
        if percent < 25 { return .red }
        if percent < 50 { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 3) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color).frame(width: max(1, 16 * min(max((percent ?? 0) / 100, 0), 1)))
            }
            .frame(width: 16, height: 3)
            Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .help(percent.map { "虚拟能量剩余 \(Int($0.rounded()))%" } ?? "虚拟能量未提供")
        .accessibilityLabel(percent.map { "虚拟能量 \(Int($0.rounded()))%" } ?? "虚拟能量未提供")
    }
}

private struct LiveSectorView: View {
    let sector: LiveSector?
    let index: Int
    var showsSegments = true
    var referenceSeconds: Double? = nil

    private var color: Color {
        sector?.overallFastest == true ? .purple : sector?.personalFastest == true ? .green : .white
    }

    /// WEC has no mini-segment statuses, so its bar compares the sector time
    /// with the best time of the same class instead of per-segment colours.
    private var paceColor: Color {
        guard let referenceSeconds,
              let raw = sector?.value,
              let seconds = LiveIslandLogic.sectorSeconds(raw) else { return .gray.opacity(0.3) }
        let delta = seconds - referenceSeconds
        if delta <= 0.001 { return .purple }
        if delta <= 0.35 { return .green }
        if delta <= 1.0 { return .yellow }
        return .gray.opacity(0.55)
    }

    private func segmentColor(_ status: Int?) -> Color {
        switch status {
        case 2048: return .yellow
        case 2049: return .green
        case 2051: return .purple
        case 2064: return .blue
        default: return .gray.opacity(0.3)
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(sector?.value.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(showsSegments ? 1 : 0.78)
                .foregroundStyle(color)
            if showsSegments {
                if let segments = sector?.segments, !segments.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(segments.indices, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1).fill(segmentColor(segments[index]))
                        }
                    }.frame(height: 4)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 4)
                }
            } else {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(paceColor)
                    .frame(height: 3)
            }
        }
        .accessibilityLabel("S\(index + 1)，\(sector?.value ?? "未提供")\(sector?.overallFastest == true ? "，全场最快" : sector?.personalFastest == true ? "，个人最快" : "")")
    }
}

private struct LiveWecTireEnergyCell: View {
    let driver: LiveDriver
    var showTire = true
    var showEnergy = true

    private var energyColor: Color {
        guard let percent = driver.energyPercent else { return .gray }
        if percent < 25 { return .red }
        if percent < 50 { return .orange }
        return .green
    }

    private var hasTire: Bool { showTire && driver.tireLabel != nil }
    private var hasEnergy: Bool { showEnergy && driver.energyPercent != nil }

    private var abilityLabel: String {
        let tire = hasTire ? driver.tireLabel.map { "轮胎 \($0)" } : nil
        let energy = hasEnergy ? driver.energyPercent.map { "虚拟能量 \(Int($0.rounded()))%" } : nil
        return [tire, energy].compactMap { $0 }.joined(separator: "，")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if hasTire {
                HStack(spacing: 5) {
                    LiveTireInline(driver: driver, fontSize: 11)
                }
            }
            if hasEnergy, let percent = driver.energyPercent {
                HStack(spacing: 4) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(energyColor)
                            .frame(width: max(1, 50 * min(max(percent / 100, 0), 1)))
                    }
                    .frame(width: 50, height: 5)
                    Text("\(Int(percent.rounded()))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(energyColor)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(abilityLabel.isEmpty ? "轮胎与能量未提供" : abilityLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(abilityLabel.isEmpty ? "轮胎与能量未提供" : abilityLabel)
    }
}

private struct LiveTrackStatusBadge: View {
    let snapshot: LiveSnapshot
    var compact = false

    private var color: Color {
        switch snapshot.trackCondition {
        case .clear: return .green
        case .yellow, .fullCourseYellow, .safetyCar: return .yellow
        case .virtualSafetyCar, .virtualSafetyCarEnding, .safetyCarEnding: return .orange
        case .red: return .red
        case .unknown: return .gray
        }
    }

    private var label: String {
        switch snapshot.sourceStatus {
        case .stale: return "赛道状态过期"
        case .disconnected: return "赛道状态不可用"
        case .connected: return snapshot.trackCondition.label
        }
    }

    var body: some View {
        Group {
            if let code = snapshot.trackCondition.code {
                HStack(spacing: compact ? 2 : 3) {
                    Image(systemName: snapshot.trackCondition.systemName)
                        .font(.system(size: compact ? 9 : 11, weight: .semibold))
                    Text(code)
                        .font(.system(size: compact ? 9 : 10, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(color)
                .padding(.horizontal, compact ? 5 : 7)
                .frame(height: compact ? 18 : 22)
                .background(color.opacity(0.16), in: Capsule())
            } else {
                Image(systemName: snapshot.trackCondition.systemName)
                    .font(.system(size: compact ? 13 : 20, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: compact ? 22 : 32, height: compact ? 18 : 28)
            }
        }
            .overlay(alignment: .bottomTrailing) {
                if snapshot.trackCondition == .safetyCarEnding || snapshot.trackCondition == .virtualSafetyCarEnding {
                    Image(systemName: "clock.fill")
                        .font(.system(size: compact ? 8 : 10))
                        .foregroundStyle(color)
                        .background(.black, in: Circle())
                }
            }
            .help(label)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("liveIsland.trackStatus")
    }
}
