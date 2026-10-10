import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let reopenNotification = Notification.Name("F1Companion.reopen")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: Self.reopenNotification, object: nil)
        return false
    }
}
