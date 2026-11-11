import SwiftUI
import PitPulseData
import PitPulseShared

@main
struct PitPulseMobileApp: App {
    @StateObject private var model = MobileModel()
    @AppStorage("mobileAppearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if CommandLine.arguments.contains("--island-preview") {
                IslandModePreviewSheet().environmentObject(model)
            } else {
                RootView().environmentObject(model)
                    .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                    .tint(PulseStyle.red)
            }
            #else
            RootView().environmentObject(model)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .tint(PulseStyle.red)
            #endif
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = ProcessInfo.processInfo.environment["PITPULSE_TAB"].flatMap(Int.init) ?? 0
    @State private var showLive = false
    @Namespace private var liveTransition
    var body: some View {
        TabView(selection: $selection) {
            OverviewScreen().tabItem { Image(systemName: "house.fill").accessibilityLabel("下一场总览") }.tag(0)
            CalendarScreen().tabItem { Image(systemName: "calendar").accessibilityLabel("赛历") }.tag(1)
            ChampionshipScreen(mode: 0).tabItem { Image(systemName: "trophy.fill").accessibilityLabel("车手积分") }.tag(2)
            ChampionshipScreen(mode: 1).tabItem { Image(systemName: "person.3.fill").accessibilityLabel("车队积分") }.tag(3)
        }
        .tint(PulseStyle.red)
        .liveBottomAccessory(isEnabled: model.hasActiveLive) {
            Group {
                Button { showLive = true } label: { LiveMiniBar() }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "live-player", in: liveTransition)
            }
        }
        .overlay(alignment: .top) {
            if let notice = model.liveNotice {
                HStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(PulseStyle.red)
                    Text(notice).font(.caption.weight(.medium))
                    Spacer(minLength: 4)
                    Button { model.liveNotice = nil; showLive = true } label: { Image(systemName: "arrow.up.right") }.accessibilityLabel("查看新开始的比赛")
                    Button { model.liveNotice = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭提示")
                }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 16).padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: model.liveNotice)
        .task(id: model.liveNotice) {
            guard model.liveNotice != nil else { return }
            do { try await Task.sleep(for: .seconds(6)); model.liveNotice = nil } catch { }
        }
        .sheet(isPresented: $model.settingsPresented) { SettingsScreen() }
        .fullScreenCover(isPresented: $showLive) {
            LiveScreen(onClose: { showLive = false })
                .navigationTransition(.zoom(sourceID: "live-player", in: liveTransition))
        }
        .task(id: model.dataContext) {
            model.startLive()
            await model.loadF1Roster()
            await model.loadCalendar()
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.startLive() } }
        .onOpenURL { url in
            if url.host == "live" { model.startLive(); showLive = true }
            if url.host == "calendar" { showLive = false; selection = 1 }
        }
    }
}

struct LiveMiniBar: View {
    @EnvironmentObject private var model: MobileModel
    var body: some View {
        HStack(spacing: 11) {
            Image(MotorsportAssetName.seriesLogoName(isWec: model.liveSnapshot.isWec)).renderingMode(.template).resizable().scaledToFit().foregroundStyle(PulseStyle.red).frame(width: 36, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.liveSnapshot.meetingName ?? model.series.title).font(.subheadline.bold()).lineLimit(1)
                Text("\(model.liveSnapshot.sessionName ?? "Live") · \(model.liveSnapshot.lapLabel)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(model.liveSnapshot.statusLabel).font(.caption2.bold()).foregroundStyle(PulseStyle.red)
            Image(systemName: "chevron.up").font(.caption.bold()).foregroundStyle(.secondary)
        }.padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
        .accessibilityElement(children: .combine).accessibilityLabel("打开 \(model.series.title) Live 比赛详情")
    }
}

enum PulseStyle {
    static let red = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.98, green: 0.25, blue: 0.23, alpha: 1) : UIColor(red: 0.78, green: 0.08, blue: 0.07, alpha: 1) })
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let border = Color.primary.opacity(0.08)
}

struct PulseSettingsButton: View {
    @EnvironmentObject private var model: MobileModel
    var body: some View {
        Button { model.settingsPresented = true } label: {
            AssetImage(name: "logo-foreground.png").frame(width: 30, height: 30)
        }.accessibilityLabel("打开 PitPulse 设置")
    }
}

struct PulseCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(PulseStyle.border))
    }
}

struct AssetImage: View {
    let name: String
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        if let image = UIImage(named: name, in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)) {
            Image(uiImage: image).renderingMode(.original).resizable().scaledToFit().accessibilityHidden(true)
        } else {
            Image(systemName: "person.crop.circle").resizable().scaledToFit().foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

struct PulseHeading: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased()).font(.caption2.weight(.bold)).tracking(3).foregroundStyle(PulseStyle.red)
            Text(title).font(.largeTitle.bold())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PulsePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension View {
    @ViewBuilder
    func liveBottomAccessory<Content: View>(isEnabled: Bool, @ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: isEnabled, content: content)
        } else if isEnabled {
            tabViewBottomAccessory(content: content)
        } else {
            self
        }
    }
}
