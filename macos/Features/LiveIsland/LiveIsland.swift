import AppKit
import Combine
import NookApp
import OSLog
import SwiftUI

@MainActor
final class LiveIslandActions: ObservableObject {
    @Published var snapshot = LiveSnapshot.disconnected()
    @Published var flag = ""
    @Published var presentation = "hidden"
    @Published var mode = "Telemetry"
    @Published var selectedNumber: String?
    @Published var showRadar = false
    @Published var messagePage = "Race Control"
    @Published var messageFilter = "all"
    @Published var messagesExpanded = false
    let map = MapStore()
    let radio = RadioPlayer()
    var expand: (() -> Void)?
    var collapse: (() -> Void)?
    var hide: (() -> Void)?
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
            self.actions.map.release(preserveCamera: true)
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

    var flag: String {
        let meeting = LiveIslandLogic.meeting(for: snapshot, in: model.meetings, now: Date())
            ?? currentPlannedSession?.meeting
        return CountryFlag.emoji(for: meeting?.countryCode) ?? ""
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
            actions.map.release()
        }
        actions.snapshot = displayed
        if incomingSnapshot != nil {
            logger.info("contentUpdated version=\(displayed.stateVersion) status=\(displayed.sourceStatus.rawValue, privacy: .public) drivers=\(displayed.drivers.count) track=\(String(describing: displayed.trackCondition), privacy: .public) panelKey=\(self.nook.window?.isKeyWindow ?? false) appActive=\(NSApp.isActive)")
        }
        let meeting = LiveIslandLogic.meeting(for: displayed, in: meetings, now: Date())
            ?? planned?.meeting
            ?? (displayed.sessionId == nil && displayed.sessionName == nil
                ? CalendarLogic.nextSession(in: meetings, now: Date())?.meeting : nil)
        actions.flag = CountryFlag.emoji(for: meeting?.countryCode) ?? ""

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

    var body: some View {
        Button { actions.expand?() } label: {
            HStack(spacing: 5) {
                if actions.flag.isEmpty {
                    Image(systemName: AppSymbol.menuBar.resolvedSystemName())
                } else {
                    Text(actions.flag)
                }
                Text(actions.snapshot.sessionType
                    ?? actions.snapshot.sessionName
                    ?? model.currentIslandSession.map { $0.session.sessionType.displayName }
                    ?? model.nextSession.map { $0.session.sessionType.displayName }
                    ?? "PitPulse")
                    .lineLimit(1)
                if actions.snapshot.sourceStatus == .connected {
                    LiveTrackStatusBadge(snapshot: actions.snapshot, compact: true)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .accessibilityLabel("\(actions.flag)，\(actions.snapshot.sessionType ?? actions.snapshot.sessionName ?? "F1 Session")，\(actions.snapshot.sessionStateLabel)，\(actions.snapshot.sourceStatus == .connected ? actions.snapshot.trackCondition.label : actions.snapshot.statusLabel)")
        .accessibilityIdentifier("liveIsland.expand")
        .accessibilityHint("展开 Live Island")
        .environment(\.colorScheme, .dark)
    }
}

struct LiveIslandCompactTrailing: View {
    @ObservedObject var model: AppModel
    @ObservedObject var actions: LiveIslandActions

    private var favorite: LiveDriver? {
        LiveIslandLogic.matchedDriver(
            favoriteId: model.favoriteDriverId,
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
                    Text(actions.snapshot.lapLabel)
                    if let favorite {
                        LiveHelmetView(model: model, driver: favorite, size: 18)
                        Text("\(MotorsportAsset.abbreviation(favorite.name ?? favorite.number)) P\(favorite.position.map(String.init) ?? "—") \(favorite.gap ?? "—")")
                            .monospacedDigit()
                    } else if model.favoriteDriverId == nil {
                        Image(systemName: "star")
                            .help("选择关注车手")
                    } else {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .help("关注车手暂无数据")
                            .accessibilityLabel("关注车手暂无数据")
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
            ? "\(actions.snapshot.statusLabel)，第 \(actions.snapshot.lapCount.map(String.init) ?? "—") 圈，关注车手 \(favorite?.name ?? "未选择")，名次 P\(favorite?.position.map(String.init) ?? "—")，间隔 \(favorite?.gap ?? "—")"
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
    private var selectedDriver: LiveDriver? { snapshot.drivers.first { $0.number == actions.selectedNumber } ?? favorite ?? snapshot.drivers.first }
    private var meeting: Meeting? { LiveIslandLogic.meeting(for: snapshot, in: model.meetings, now: Date()) }

    private var snapshot: LiveSnapshot { actions.snapshot }
    private var hasTiming: Bool { snapshot.sourceStatus == .connected }
    private var title: String {
        let components = [snapshot.meetingName, snapshot.sessionName ?? snapshot.sessionType].compactMap { $0 }
        return components.isEmpty ? model.nextMeeting?.name ?? "PitPulse" : components.joined(separator: " · ")
    }
    private var favorite: LiveDriver? {
        LiveIslandLogic.matchedDriver(
            favoriteId: model.favoriteDriverId,
            favorites: model.favoriteDrivers,
            drivers: hasTiming ? snapshot.drivers : []
        )
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

    private var followControls: some View {
        HStack(spacing: 10) {
            if let selectedDriver { LiveHelmetView(model: model, driver: selectedDriver, size: 28) }
            Menu {
                Button("不关注") { model.setFavoriteDriver(nil) }
                ForEach(model.favoriteDrivers) { driver in
                    Button { model.setFavoriteDriver(driver.id) } label: {
                        if model.favoriteDriverId == driver.id {
                            Label(driver.name, systemImage: "checkmark")
                        } else {
                            Text(driver.name)
                        }
                    }
                }
            } label: {
                Image(systemName: model.favoriteDriverId == nil ? "star" : "star.fill")
                    .foregroundStyle(model.favoriteDriverId == nil ? Color.secondary : .yellow)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.favoriteDrivers.isEmpty)
            .help("选择或切换关注车手")
            .accessibilityLabel("选择关注车手")
            .accessibilityIdentifier("liveIsland.favoriteDriver")
            if let driver = selectedDriver {
                Text("#\(driver.number) \(driver.name ?? "车手")")
                    .font(.caption.weight(.semibold)).lineLimit(1)
                Text("P\(driver.position.map(String.init) ?? "—") · \(driver.gap ?? "—")")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
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
                Text(actions.flag).font(.headline)
                Text(title).font(.headline).lineLimit(1)
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
                    Text(snapshot.lapLabel).font(.caption.weight(.semibold)).monospacedDigit()
                    LiveTrackStatusBadge(snapshot: snapshot, compact: true)
                } else { LiveWaitingIndicator(detail: snapshot.statusLabel) }
                if mode == "Live Map" {
                    Button { actions.showRadar.toggle() } label: {
                        Image(systemName: "cloud.rain").foregroundStyle(showRadar ? Color.blue : Color.secondary)
                    }.buttonStyle(.borderless).help("历史降雨雷达")
                        .accessibilityLabel("历史降雨雷达").accessibilityValue(showRadar ? "开启" : "关闭")
                }
            }
            if mode == "Telemetry" { LiveTelemetryView(driver: selectedDriver, snapshot: snapshot) }
            ScrollView {

                VStack(alignment: .leading, spacing: 10) {

                    if mode == "Telemetry" {
                        if hasTiming {
                            HStack(spacing: 8) {
                                HStack(spacing: 7) {
                                    Image(systemName: "star").frame(width: 17)
                                    Text("位置 / 车手")
                                }.frame(width: 224, alignment: .leading)
                                timingHeader("Gap", width: 58)
                                timingHeader("Interval", width: 58)
                                timingHeader("上一圈", width: 76)
                                timingHeader("最佳圈", width: 76)
                                ForEach(0..<3) { index in timingHeader("S\(index + 1)", width: 88) }
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            LazyVStack(spacing: 6) {
                                ForEach(snapshot.drivers, id: \.number) { driver in
                                    let driverID = LiveIslandLogic.followableDriverID(for: driver, favorites: model.favoriteDrivers, drivers: snapshot.drivers)
                                    let followed = driverID != nil && driverID == model.favoriteDriverId
                                    HStack(spacing: 0) {
                                            Button {
                                                if let driverID { model.setFavoriteDriver(followed ? nil : driverID) }
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
                                                    LiveHelmetView(model: model, driver: driver, size: 32)
                                                    VStack(alignment: .leading, spacing: 3) {
                                                        Text(driver.name ?? "#\(driver.number)").font(.caption.weight(.semibold)).lineLimit(1)
                                                        Text(driver.retired == true ? "已退赛" : driver.inPit == true ? "进站中" : driver.team ?? "—")
                                                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                                    }
                                                }.frame(width: 199, alignment: .leading)
                                                timingValue(driver.gap, label: "距领先车手", width: 58)
                                                timingValue(driver.interval, label: "距前车", width: 58)
                                                timingValue(driver.lastLap, label: "上一圈", width: 76)
                                                timingValue(driver.bestLap, label: "最佳圈", width: 76)
                                                ForEach(0..<3) { index in
                                                    LiveSectorView(sector: driver.sectors.flatMap { index < $0.count ? $0[index] : nil }, index: index)
                                                        .frame(width: 88)
                                                }
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 8)
                                            .background(followed ? Color.blue.opacity(0.22) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            if let driverID { Button(followed ? "取消关注" : "关注车手") { model.setFavoriteDriver(followed ? nil : driverID) } }
                                        }
                                        .help("点击查看车辆遥测，右键可关注车手")
                                        .accessibilityHint("激活后选择这名车手查看遥测")
                                        .accessibilityValue(followed ? "已关注" : "未关注")
                                        .accessibilityIdentifier("liveIsland.select.\(driver.number)")
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                            }

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
                    MapView(store: map, meeting: meeting, snapshot: snapshot, selected: selectedDriver?.number, radar: showRadar, active: mode == "Live Map" && actions.presentation == "expanded")
                        .frame(height: mode == "Live Map" ? (showRadar ? 210 : 250) : 0)
                        .opacity(mode == "Live Map" ? 1 : 0)
                        .allowsHitTesting(mode == "Live Map")
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .task(id: "\(model.serverAddress)-\(meeting?.id ?? "none")-\(actions.presentation)") {
            guard actions.presentation == "expanded" else { return }
            await map.load(model: model, meeting: meeting)
            map.onDriver = { actions.selectedNumber = $0 }
        }
        .onChange(of: actions.presentation) { _, value in
            if value != "expanded" { radio.stop(); map.pause() }
            if value == "hidden" { map.release(preserveCamera: true) }
        }
        .onChange(of: model.favoriteDriverId) { _, _ in actions.selectedNumber = nil }

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

    var body: some View {
        Group {
            if let id = LiveIslandLogic.rosterID(for: driver, favorites: model.favoriteDrivers),
               let image = MotorsportAsset.image(kind: .helmet, id: id, season: model.selectedSeason) {
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

private struct LiveSectorView: View {
    let sector: LiveSector?
    let index: Int

    private var color: Color {
        sector?.overallFastest == true ? .purple : sector?.personalFastest == true ? .green : .white
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
                .foregroundStyle(color)
            if let segments = sector?.segments, !segments.isEmpty {
                HStack(spacing: 2) {
                    ForEach(segments.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1).fill(segmentColor(segments[index]))
                    }
                }.frame(height: 4)
            } else {
                Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 4)
            }
        }
        .accessibilityLabel("S\(index + 1)，\(sector?.value ?? "未提供")\(sector?.overallFastest == true ? "，全场最快" : sector?.personalFastest == true ? "，个人最快" : "")")
    }
}

private struct LiveTrackStatusBadge: View {
    let snapshot: LiveSnapshot
    var compact = false

    private var color: Color {
        switch snapshot.trackCondition {
        case .clear: return .green
        case .yellow, .safetyCar: return .yellow
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
        Image(systemName: snapshot.trackCondition.systemName)
            .font(.system(size: compact ? 13 : 20, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: compact ? 22 : 32, height: compact ? 18 : 28)
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
