import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let reopenNotification = Notification.Name("F1Companion.reopen")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // PitPulse is a menu bar app; the Settings window temporarily promotes
        // the app to `.regular` via SettingsWindowActivation and demotes it back
        // here on close.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if SettingsWindowActivation.shared.bringToFront() {
            return false
        }
        NotificationCenter.default.post(name: Self.reopenNotification, object: nil)
        return false
    }
}
