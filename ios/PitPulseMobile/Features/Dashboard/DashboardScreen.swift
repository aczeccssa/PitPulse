import SharedComponents
import SharedData
import SwiftUI
import UIKit

enum DashboardTab: Int, CaseIterable, Identifiable {
    case home, results, headToHead, drivers, constructors

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .results: "Results"
        case .headToHead: "Head to Head"
        case .drivers: "Drivers"
        case .constructors: "Constructors"
        }
    }

    var headerTitle: String { self == .home ? "Pit Pulse" : title }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .results: "flag.checkered"
        case .headToHead: "arrow.left.arrow.right"
        case .drivers: "person.text.rectangle.fill"
        case .constructors: "trophy.fill"
        }
    }
}

struct DashboardScreen<Header: View>: View {
    let tab: DashboardTab
    let fromHome: Bool
    let header: Header
    @Binding var showCalendar: Bool
    let openTab: (DashboardTab) -> Void
    @State private var showsDriverStandings: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visitedConsistency = false
    @State private var showConsistency: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["PITPULSE_DASHBOARD_SUBTAB"] == "consistency"
        #else
        false
        #endif
    }()

    init(tab: DashboardTab, fromHome: Bool, header: Header, showCalendar: Binding<Bool>,
         openTab: @escaping (DashboardTab) -> Void) {
        self.tab = tab
        self.fromHome = fromHome
        self.header = header
        _showCalendar = showCalendar
        self.openTab = openTab
        _showsDriverStandings = State(initialValue: true)
    }

    var body: some View {
        switch tab {
        case .home:
            WebHomeScreen(header: header, showCalendar: $showCalendar, openTab: openTab)
        case .constructors:
            NavigationStack {
                ChampionshipScreen(constructorsOnly: true)
                    .dashboardHeader(header)
            }
            .environment(\.usesDashboardCardStyle, true)
        default:
            NavigationStack {
                Group {
                    switch tab {
                    case .results:
                        SeasonResultsIndex()
                    case .headToHead:
                        VStack(spacing: 8) {
                            PulseSectionPicker(
                                sections: [(false, "Head to Head"), (true, "Consistency")],
                                selection: $showConsistency
                            ).padding(.horizontal, 16)
                            ZStack {
                                TeammateComparisonBoard()
                                    .opacity(showConsistency ? 0 : 1)
                                    .allowsHitTesting(!showConsistency)
                                    .accessibilityHidden(showConsistency)
                                if showConsistency || visitedConsistency {
                                    DriverConsistency()
                                        .opacity(showConsistency ? 1 : 0)
                                        .allowsHitTesting(showConsistency)
                                        .accessibilityHidden(!showConsistency)
                                }
                            }
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showConsistency)
                            .onChange(of: showConsistency, initial: true) { _, shown in
                                if shown { visitedConsistency = true }
                            }
                        }
                    case .drivers:
                        DriversDashboard(showsStandings: $showsDriverStandings)
                    default:
                        EmptyView()
                    }
                }
                .background(PulseStyle.background)
                .dashboardHeader(header)
            }
        }
    }
}

extension View {
    func dashboardDetail() -> some View {
        modifier(DashboardDetail())
    }

    func dashboardHeader<Header: View>(_ header: Header) -> some View {
        safeAreaInset(edge: .top, spacing: 0) { header }
            .toolbar(.hidden, for: .navigationBar)
            .modifier(DashboardLiveBarSpace())
    }
}

extension EnvironmentValues {
    @Entry var dashboardLiveBarFrame: ((CGRect) -> Void)? = nil
    @Entry var dashboardLivePage: ((UUID?) -> Void)? = nil
    @Entry var dashboardLiveDetailFrame: ((UUID, CGRect) -> Void)? = nil
}

private struct DashboardLiveBarSpace: ViewModifier {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dashboardLiveBarFrame) private var reportFrame
    @Environment(\.dashboardLivePage) private var showPage

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 6) {
            if model.hasActiveLive, let reportFrame {
                Color.clear
                    .frame(maxWidth: 640)
                    .frame(height: 48)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { reportFrame($0) }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { showPage?(nil) }
        .background { DashboardTabBarTransition(hidesTabBar: false) { showPage?(nil) } }
    }
}

private struct DashboardDetail: ViewModifier {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dashboardLiveDetailFrame) private var reportFrame
    @Environment(\.dashboardLivePage) private var showPage
    @State private var id = UUID()

    func body(content: Content) -> some View {
        if let reportFrame {
            content
                .contentMargins(.bottom, model.hasActiveLive ? 64 : 0, for: .scrollContent)
                .onGeometryChange(for: CGRect.self) { geometry in
                    geometry.frame(in: .global).inset(by: geometry.safeAreaInsets)
                } action: { frame in
                    reportFrame(id, frame)
                }
                .onAppear { showPage?(id) }
                .background { DashboardTabBarTransition(hidesTabBar: true) { showPage?(id) } }
        } else {
            content
        }
    }
}

private struct DashboardTabBarTransition: UIViewControllerRepresentable {
    let hidesTabBar: Bool
    let didAppear: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(hidesTabBar: hidesTabBar, didAppear: didAppear)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.didAppear = didAppear
    }

    final class Controller: UIViewController {
        let hidesTabBar: Bool
        var didAppear: () -> Void

        init(hidesTabBar: Bool, didAppear: @escaping () -> Void) {
            self.hidesTabBar = hidesTabBar
            self.didAppear = didAppear
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard let tabs = tabBarController else { return }
            let bar = tabs.tabBar
            let wasHidden = tabs.isTabBarHidden || bar.accessibilityElementsHidden
            let hiddenTransform = offscreenTransform(in: tabs)
            let coordinator = navigationController?.transitionCoordinator ?? transitionCoordinator

            // UIKit drives the same animation during an interactive back swipe, including cancellation.
            if tabs.isTabBarHidden, !hidesTabBar {
                bar.transform = hiddenTransform
                tabs.setTabBarHidden(false, animated: false)
                bar.transform = hiddenTransform
            }
            guard wasHidden != hidesTabBar, !UIAccessibility.isReduceMotionEnabled, animated,
                  let coordinator else {
                applyVisibility(in: tabs, hidden: hidesTabBar)
                return
            }
            let didAnimate = coordinator.animate(alongsideTransition: { _ in
                bar.transform = self.hidesTabBar ? hiddenTransform : .identity
            }, completion: { [weak self] context in
                guard let self else { return }
                self.applyVisibility(in: tabs, hidden: context.isCancelled ? wasHidden : self.hidesTabBar)
            })
            if !didAnimate { applyVisibility(in: tabs, hidden: hidesTabBar) }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let tabs = tabBarController else { return }
            // Some gestures settle without a coordinator on the destination.
            applyVisibility(in: tabs, hidden: hidesTabBar)
            didAppear()
        }

        private func applyVisibility(in tabs: UITabBarController, hidden: Bool) {
            if tabs.isTabBarHidden != hidden {
                tabs.setTabBarHidden(hidden, animated: false)
            }
            tabs.tabBar.transform = hidden ? offscreenTransform(in: tabs) : .identity
            tabs.tabBar.accessibilityElementsHidden = hidden
        }

        private func offscreenTransform(in tabs: UITabBarController) -> CGAffineTransform {
            let distance = tabs.tabBar.bounds.height + tabs.view.safeAreaInsets.bottom + 24
            return CGAffineTransform(translationX: 0, y: distance)
        }
    }
}

private extension CGRect {
    func inset(by insets: EdgeInsets) -> CGRect {
        CGRect(x: minX + insets.leading, y: minY + insets.top,
               width: max(0, width - insets.leading - insets.trailing),
               height: max(0, height - insets.top - insets.bottom))
    }
}

enum WebDashboardStyle {
    static let homeBackground = adaptive(dark: 0x02050b, light: 0xf5f5f5)
    static let homePanel = adaptive(dark: 0x080e18, light: 0xffffff)
    static let homeLine = adaptive(dark: 0x1b2230, light: 0xe8edf3)
    static let homeText = adaptive(dark: 0xf5f7fb, light: 0x080e1c)
    static let homeMuted = adaptive(dark: 0x9da5b4, light: 0x64748b)

    static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

extension View {
    func dashboardPanel<Fill: ShapeStyle>(_ fill: Fill, line: Color = WebDashboardStyle.homeLine) -> some View {
        background(fill, in: PulseStyle.cardShape)
            .overlay { PulseStyle.cardShape.strokeBorder(line).allowsHitTesting(false) }
            .containerShape(PulseStyle.cardShape)
            .pulseReveal()
    }
}

enum DashboardArt {
    @MainActor static func image(_ kind: MotorsportAssetName.Kind, id: String, season: Int) -> UIImage? {
        image(named: MotorsportAssetName.name(kind: kind, id: id, season: season))
    }

    @MainActor static func image(named name: String, traits: UITraitCollection? = nil) -> UIImage? {
        MotorsportImages.uiImage(named: name, traits: traits)
    }

    static func teamColor(_ id: String) -> Color {
        switch LiveIslandLogic.assetSlug(id) {
        case "mercedes": Color(red: 0.04, green: 0.73, blue: 0.64)
        case "ferrari": Color(red: 0.91, green: 0.15, blue: 0.22)
        case "mclaren": Color(red: 1, green: 0.52, blue: 0.16)
        case "red-bull", "red-bull-racing": Color(red: 0.25, green: 0.43, blue: 0.97)
        case "williams": Color(red: 0.30, green: 0.68, blue: 0.96)
        case "alpine": Color(red: 0.78, green: 0.36, blue: 0.67)
        case "rb", "racing-bulls", "alphatauri": Color(red: 0.41, green: 0.54, blue: 0.98)
        case "haas": Color(red: 0.61, green: 0.68, blue: 0.73)
        case "audi": Color(red: 0.80, green: 0.24, blue: 0.36)
        case "cadillac": Color(red: 0.77, green: 0.63, blue: 0.20)
        case "sauber": Color(red: 0.28, green: 0.71, blue: 0.27)
        case "aston-martin": Color(red: 0.03, green: 0.59, blue: 0.43)
        default: Color(red: 0.40, green: 0.53, blue: 0.71)
        }
    }
}
