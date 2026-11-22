import SharedComponents
import SharedData
import SwiftUI
import UIKit

enum DashboardTab: Int, CaseIterable, Identifiable {
    case home, results, headToHead, drivers, constructors

    case driverStandings, consistency
    case settings = 10, calendar

    static let phoneTabs: [Self] = [.home, .results, .headToHead, .drivers, .constructors]
    static let padTabs: [Self] = [
        .home, .calendar, .driverStandings, .constructors, .results, .headToHead,
        .consistency, .settings
    ]

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .results: "Results"
        case .headToHead: "Head to Head"
        case .drivers: "Drivers"
        case .constructors: "Constructors"
        case .driverStandings: "Driver Standings"
        case .consistency: "Consistency"
        case .settings: "Settings"
        case .calendar: "Calendar"
        }
    }

    var headerTitle: String { self == .home ? "Pit Pulse" : title }

    var webNavigationIcon: String? {
        switch self {
        case .home: "home"
        case .driverStandings: "driver-standings"
        case .constructors: "constructor-standings"
        case .results: "results"
        case .drivers: "drivers"
        case .headToHead: "head-to-head"
        case .consistency: "consistency"
        case .settings, .calendar: nil
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .results: "flag.checkered"
        case .headToHead: "arrow.left.arrow.right"
        case .drivers: "person.text.rectangle.fill"
        case .constructors: "trophy.fill"
        case .driverStandings: "list.number"
        case .consistency: "waveform.path"
        case .settings: "gearshape"
        case .calendar: "calendar"
        }
    }
}

enum DriverProfileDestination: Hashable {
    case stats(StandingEntry)
    case comparison(String, String?)
}

struct DashboardScreen<Header: View>: View {
    let padWorkspace: Bool
    let tab: DashboardTab
    let fromHome: Bool
    let header: Header
    @Binding var showCalendar: Bool
    var profileTarget: DriverProfileDestination?
    let consistencyFilter: Binding<Bool>
    let resultsTarget: (Meeting, Session)?
    let openResultsSession: (Meeting, Session) -> Void
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

    init(padWorkspace: Bool = false, tab: DashboardTab, fromHome: Bool, header: Header, showCalendar: Binding<Bool>,
         resultsTarget: (Meeting, Session)? = nil, profileTarget: DriverProfileDestination? = nil,
         consistencyFilter: Binding<Bool>,
         openResultsSession: @escaping (Meeting, Session) -> Void,
         openTab: @escaping (DashboardTab) -> Void) {
        self.padWorkspace = padWorkspace
        self.tab = tab
        self.fromHome = fromHome
        self.header = header
        _showCalendar = showCalendar
        self.resultsTarget = resultsTarget
        self.profileTarget = profileTarget
        self.consistencyFilter = consistencyFilter
        self.openResultsSession = openResultsSession
        self.openTab = openTab
        _showsDriverStandings = State(initialValue: !padWorkspace || tab == .driverStandings)
    }

    private var initialDriverStanding: StandingEntry? {
        if case let .stats(entry) = profileTarget { return entry }
        return nil
    }

    var body: some View {
        switch tab {
        case .home:
            WebHomeScreen(header: header, showCalendar: $showCalendar, openResultsSession: openResultsSession, openTab: openTab)
        case .settings:
            SettingsScreen(embedded: true)
                .modifier(DashboardLiveBarSpace())
        case .constructors:
            NavigationStack {
                ChampionshipScreen(constructorsOnly: true, tabletWebLayout: padWorkspace)
                    .dashboardHeader(header)
            }
            .environment(\.usesDashboardCardStyle, true)
        default:
            NavigationStack {
                Group {
                    switch tab {
                    case .results:
                        SeasonResultsIndex(initialMeeting: resultsTarget?.0, initialSession: resultsTarget?.1)
                    case .headToHead where padWorkspace:
                        if case let .comparison(driver, teammate) = profileTarget {
                            TeammateComparisonBoard(initialDriver: driver, teammate: teammate, tabletWebLayout: true)
                                .id(profileTarget)
                        } else {
                            TeammateComparisonBoard(tabletWebLayout: true)
                        }
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
                    case .calendar:
                        TabletRaceCalendar()
                    case .driverStandings:
                        DriversDashboard(showsStandings: $showsDriverStandings, showsSectionPicker: false,
                                         initialStanding: initialDriverStanding)
                    case .drivers:
                        DriversDashboard(showsStandings: $showsDriverStandings)
                    case .consistency:
                        DriverConsistency(tabletWebLayout: padWorkspace, tabletFilter: consistencyFilter)
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
    @Entry var openDashboardDriverProfile: ((DriverProfileDestination) -> Void)? = nil
    @Entry var dashboardTabPlatterFrame: ((CGRect) -> Void)? = nil
    @Entry var dashboardLiveBarFrame: ((CGRect) -> Void)? = nil
    @Entry var dashboardLivePage: ((UUID?) -> Void)? = nil
    @Entry var dashboardLiveDetailFrame: ((UUID, CGRect) -> Void)? = nil
}

private struct DashboardLiveBarSpace: ViewModifier {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dashboardLiveBarFrame) private var reportFrame
    @Environment(\.dashboardTabPlatterFrame) private var reportTabPlatter
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
        .background {
            if let showPage {
                DashboardTabBarTransition(hidesTabBar: false, reportTabPlatter: reportTabPlatter) { showPage(nil) }
            }
        }
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
                .background { DashboardTabBarTransition(hidesTabBar: UIDevice.current.userInterfaceIdiom != .pad) { showPage?(id) } }
        } else {
            content
        }
    }
}

private struct DashboardTabBarTransition: UIViewControllerRepresentable {
    let hidesTabBar: Bool
    var reportTabPlatter: ((CGRect) -> Void)? = nil
    let didAppear: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(hidesTabBar: hidesTabBar, didAppear: didAppear)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.didAppear = didAppear
        controller.reportTabPlatter = reportTabPlatter
    }

    final class Controller: UIViewController {
        let hidesTabBar: Bool
        var didAppear: () -> Void
        var reportTabPlatter: ((CGRect) -> Void)?

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
            reportPlatterAfterLayout()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            reportPlatterAfterLayout()
        }

        private func reportPlatterAfterLayout() {
            guard reportTabPlatter != nil else { return }
            Task { @MainActor [weak self] in
                guard let self, let bar = tabBarController?.tabBar, let window = bar.window,
                      viewIfLoaded?.window === window else { return }
                // UITabBar spans the window. The inset view containing the tab controls is the visible glass.
                let platter = bar.subviews.first { candidate in
                    !candidate.isHidden && candidate.bounds.width > bar.bounds.width / 2
                        && candidate.bounds.width < bar.bounds.width && containsTabControl(candidate)
                }
                if let platter {
                    reportTabPlatter?(platter.convert(platter.bounds, to: window))
                }
            }
        }

        private func containsTabControl(_ view: UIView) -> Bool {
            view is UIControl || view.subviews.contains(where: containsTabControl)
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

    static func chartTeamColor(_ teamID: String, adjustsForLight: Bool = true) -> Color {
        let colors: (dark: UInt32, light: UInt32)
        switch LiveIslandLogic.assetSlug(teamID) {
        case "red-bull", "red-bull-racing": colors = (0x3671c6, 0x3671c6)
        case "mercedes": colors = (0x27f4d2, 0x008f80)
        case "mclaren": colors = (0xff8000, 0xff8000)
        case "ferrari": colors = (0xe8002d, 0xe8002d)
        case "williams": colors = (0x64c4ff, 0x187db0)
        case "rb", "racing-bulls": colors = (0x6692ff, 0x6692ff)
        case "aston-martin": colors = (0x229971, 0x229971)
        case "alpine": colors = (0x0093cc, 0x0093cc)
        case "haas": colors = (0xb6babd, 0x727b85)
        case "sauber": colors = (0x52e252, 0x52e252)
        case "alfa", "alfa-romeo": colors = (0xc92d4b, 0xc92d4b)
        case "alphatauri": colors = (0x5e8faa, 0x5e8faa)
        case "audi": colors = (0xf50537, 0xf50537)
        case "cadillac": colors = (0xc9b037, 0x8d7a19)
        default: return DashboardArt.teamColor(teamID)
        }
        return WebDashboardStyle.adaptive(dark: colors.dark, light: adjustsForLight ? colors.light : colors.dark)
    }

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
