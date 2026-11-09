import SwiftUI

@main
struct PitPulseMobileApp: App {
    @StateObject private var model = MobileModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: MobileModel

    @State private var selection: Int = ProcessInfo.processInfo.environment["PITPULSE_TAB"].flatMap(Int.init) ?? 0

    var body: some View {
        TabView(selection: $selection) {
            CalendarScreen()
                .tabItem { Label("赛程", systemImage: "calendar") }
                .tag(0)
            LiveScreen()
                .tabItem { Label("Live", systemImage: "flag.checkered") }
                .tag(1)
            SettingsScreen()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(2)
        }
        .tint(.red)
    }
}
