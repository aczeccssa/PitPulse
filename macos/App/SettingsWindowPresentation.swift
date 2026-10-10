import AppKit
import SwiftUI

/// PitPulse runs as an accessory (menu bar) app, so a plain Settings scene
/// opens a window that never appears in the Dock or the app switcher. While
/// the Settings window exists this controller promotes the app to `.regular`
/// (Dock tile, Cmd+Tab, standard Window menu) and demotes it back to
/// `.accessory` when the window closes.
@MainActor
final class SettingsWindowActivation: NSObject {
    static let shared = SettingsWindowActivation()

    private weak var hostWindow: NSWindow?
    private var didPromote = false

    func track(_ window: NSWindow?) {
        guard let window, window !== hostWindow else { return }
        NotificationCenter.default.removeObserver(self)
        hostWindow = window
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: window)
        center.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: window)
        promote()
        DispatchQueue.main.async { [weak window] in
            window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        promote()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        demote()
    }

    private func promote() {
        guard !didPromote, NSApp.activationPolicy() == .accessory else { return }
        didPromote = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    private func demote() {
        guard didPromote else { return }
        didPromote = false
        NSApp.setActivationPolicy(.accessory)
    }

    /// Brings the open Settings window to the front. Returns `false` when the
    /// app has no Settings window to show.
    func bringToFront() -> Bool {
        guard let hostWindow, hostWindow.isVisible else { return false }
        promote()
        NSApp.activate()
        hostWindow.makeKeyAndOrderFront(nil)
        return true
    }
}

/// Reports the window that hosts the Preferences view to `SettingsWindowActivation`.
struct SettingsWindowProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            SettingsWindowActivation.shared.track(window)
        }
    }
}
