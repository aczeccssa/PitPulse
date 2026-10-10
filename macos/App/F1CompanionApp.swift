import SwiftUI

@main
struct F1CompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    @StateObject private var liveIsland: LiveIslandController

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        _liveIsland = StateObject(wrappedValue: LiveIslandController(model: model))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(model)
                .environmentObject(model.liveStore)
                .environmentObject(liveIsland)
        } label: {
            StatusMenuLabel(symbol: .menuBar)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .environmentObject(model)
                .frame(width: 560, height: 560)
        }
    }
}
