import SwiftUI

@main
struct F1CompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(model)
        } label: {
            StatusMenuLabel(symbol: model.statusSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .environmentObject(model)
                .frame(width: 560, height: 430)
        }
    }
}
