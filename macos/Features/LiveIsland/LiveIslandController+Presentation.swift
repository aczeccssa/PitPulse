import AppKit
import Combine
import NookApp
import OSLog
import SwiftUI
import SharedData


extension LiveIslandController {
    func updateCollapseBehavior(automatic: Bool? = nil, expanded: Bool? = nil) {
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

    func collapseForOutsideClick() {
        guard nook.state == .expanded, !model.notchCollapseOnMouseExit,
              transientPanels == 0, !nook.isHovering else { return }
        actions.collapse?()
    }

    func stopClickMonitoring() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
    }

    func autoShowPreferenceChanged(_ enabled: Bool) {
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

    func diagnose(_ event: String) {
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

    func configurePanel() {
        nook.configureWindow { window in
            window.hidesOnDeactivate = false
            (window as? NSPanel)?.becomesKeyOnlyIfNeeded = true
        }
    }

    func scheduleHide(for key: String) {
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
