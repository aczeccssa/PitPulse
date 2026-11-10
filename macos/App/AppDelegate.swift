import AppKit
import SwiftUI
import PitPulseShared

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var widgetHandler: ((WidgetDestination) -> Void)?
    private static var widgetCalendarWindow: NSWindowController?

    static func configureWidgetRoutes(model: AppModel) {
        widgetHandler = { destination in
            switch destination {
            case .calendar:
                if widgetCalendarWindow == nil {
                    let content = CalendarView().environmentObject(model)
                        .frame(minWidth: 480, minHeight: 640)
                        .task { await model.refreshNow() }
                    let window = NSWindow(contentViewController: NSHostingController(rootView: content))
                    window.title = "PitPulse · 赛历"
                    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
                    window.setContentSize(NSSize(width: 560, height: 720))
                    window.isReleasedWhenClosed = false
                    window.center()
                    widgetCalendarWindow = NSWindowController(window: window)
                }
                widgetCalendarWindow?.showWindow(nil)
                widgetCalendarWindow?.window?.makeKeyAndOrderFront(nil)
            case .live:
                model.setLiveSeries(.f1)
                NotificationCenter.default.post(name: Self.reopenNotification, object: nil)
            }
            NSApp.activate()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let destination = WidgetDestination(url: url) else { continue }
            Self.widgetHandler?(destination)
        }
    }
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
