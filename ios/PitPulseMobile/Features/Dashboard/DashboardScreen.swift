import SharedComponents
import SharedData
import SwiftUI

enum DashboardTab: Int, CaseIterable, Identifiable {
    case home, results, headToHead, drivers, constructors

    var id: Self { self }
    var usesEnglishPresentation: Bool { self != .drivers }

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

    init(tab: DashboardTab, fromHome: Bool, header: Header, openTab: @escaping (DashboardTab) -> Void) {
        self.tab = tab
        self.fromHome = fromHome
        self.header = header
        self.openTab = openTab
        _showsDriverStandings = State(initialValue: fromHome)
    }

    var body: some View {
        switch tab {
        case .home:
            WebHomeScreen(header: header, openTab: openTab)
        case .constructors:
            NavigationStack {
                ChampionshipScreen(constructorsOnly: true)
                    .dashboardHeader(header)
            }
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
                        VStack(spacing: 8) {
                            PulseSectionPicker(sections: [(false, "车手"), (true, "积分榜")],
                                               selection: $showsDriverStandings)
                                .padding(.horizontal, 16)
                            if showsDriverStandings { ChampionshipScreen(driversOnly: true) }
                            else { DriverDirectory() }
                        }
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
    func dashboardHeader<Header: View>(_ header: Header) -> some View {
        safeAreaInset(edge: .top, spacing: 0) { header }
            .toolbar(.hidden, for: .navigationBar)
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
