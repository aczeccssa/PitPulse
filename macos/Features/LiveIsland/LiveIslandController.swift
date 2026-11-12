import AppKit
import Combine
import NookApp
import OSLog
import SwiftUI
import SharedData

@MainActor
final class LiveIslandController: ObservableObject {
    static let finishDisplayDuration: Duration = .seconds(30)

    @Published private(set) var isVisible = false
    @Published private(set) var lastKnownSnapshot: LiveSnapshot?

    let model: AppModel
    let nook: Nook<LiveIslandExpandedView, LiveIslandCompactLeading, LiveIslandCompactTrailing>

    let logger = Logger(subsystem: "com.pitpulse.F1Companion", category: "LiveIsland")
    let liveStore: LiveStore
    let actions: LiveIslandActions
    var cancellables = Set<AnyCancellable>()
    var finishTask: Task<Void, Never>?
    var finishSessionKey: String?
    var activeSessionKey: String?
    var automaticallyShown = false
    var dismissedSessionKey: String?
    var plannedSessionKey: String?
    var transientPanels = 0
    var clickMonitors: [Any] = []


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

    func reconcile(snapshot incomingSnapshot: LiveSnapshot? = nil, meetings incomingMeetings: [Meeting]? = nil, autoShowEnabled: Bool? = nil) {
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

}
