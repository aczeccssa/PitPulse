import SharedComponents
import SwiftUI
import SharedData
import UIKit

@main
struct PitPulseMobileApp: App {
    @UIApplicationDelegateAdaptor(MobileOrientationDelegate.self) private var orientationDelegate
    @StateObject private var model = MobileModel()
    @AppStorage("mobileAppearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                Color.clear
            } else if CommandLine.arguments.contains("--widget-preview") {
                NavigationStack { WidgetPreviewGallery().background(PulseStyle.background) }
                    .environment(\.locale, .pulseEnglish)
                    .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                    .tint(PulseStyle.red)
            } else if CommandLine.arguments.contains("--island-preview") {
                IslandModePreviewSheet().environmentObject(model)
            } else {
                RootView().environmentObject(model)
                    .environment(\.locale, .pulseEnglish)
                    .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                    .tint(PulseStyle.red)
            }
            #else
            RootView().environmentObject(model)
                .environment(\.locale, .pulseEnglish)
                    .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .tint(PulseStyle.red)
            #endif
        }
        .backgroundTask(.appRefresh(MobileModel.activityRefreshIdentifier)) {
            await model.refreshLiveActivityInBackground()
        }
    }
}

final class MobileOrientationDelegate: NSObject, UIApplicationDelegate {
    private static weak var landscapeScene: UIWindowScene?
    private static weak var liveScene: UIWindowScene?

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        guard let scene = window?.windowScene else { return .portrait }
        if scene === Self.landscapeScene { return .landscapeRight }
        return scene === Self.liveScene ? .allButUpsideDown : .portrait
    }

    static func allowLiveRotation(in scene: UIWindowScene) {
        guard liveScene !== scene else { return }
        liveScene = scene
        updateOrientationSupport(in: scene)
    }

    static func endLiveRotation() {
        guard let scene = liveScene else { return }
        liveScene = nil
        request(.portrait, in: scene)
    }

    static func enterLandscape(in scene: UIWindowScene) {
        landscapeScene = scene
        request(.landscapeRight, in: scene)
    }

    static func leaveLandscape() {
        guard let scene = landscapeScene else { return }
        landscapeScene = nil
        request(.portrait, in: scene)
    }

    private static func request(_ orientations: UIInterfaceOrientationMask, in scene: UIWindowScene) {
        UIView.performWithoutAnimation {
            updateOrientationSupport(in: scene)
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
        }
    }

    private static func updateOrientationSupport(in scene: UIWindowScene) {
        var controller = scene.keyWindow?.rootViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
        }
    }
}

struct LiveRotationAccess: UIViewRepresentable {
    var onOrientationChange: (UIInterfaceOrientation) -> Void

    func makeUIView(context: Context) -> Anchor { Anchor() }
    func updateUIView(_ view: Anchor, context: Context) {
        view.onOrientationChange = onOrientationChange
    }

    final class Anchor: UIView {
        var onOrientationChange: ((UIInterfaceOrientation) -> Void)?
        private var geometryObservation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            geometryObservation = nil
            guard let scene = window?.windowScene else { return }
            MobileOrientationDelegate.allowLiveRotation(in: scene)
            geometryObservation = scene.observe(\.effectiveGeometry, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, let scene = window?.windowScene else { return }
                    onOrientationChange?(scene.effectiveGeometry.interfaceOrientation)
                }
            }
        }
    }
}

struct LandscapeCover<Background: ShapeStyle, Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLandscape = false
    @State private var isClosing = false
    let background: Background
    @ViewBuilder let content: (@escaping () -> Void) -> Content

    var body: some View {
        LandscapeCanvas(content: content(close)) {
            // Let UIKit finish the unanimated orientation update before the cover zooms back.
            DispatchQueue.main.async {
                if isClosing { dismiss() }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= $0.size.height } action: { isLandscape = $0 }
        .background { Rectangle().fill(background).ignoresSafeArea() }
        .presentationBackground(background)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .task(id: isClosing) {
            guard isClosing else { return }
            // Keep dismissal available if the system declines the portrait request.
            try? await Task.sleep(for: .milliseconds(900))
            if !Task.isCancelled { dismiss() }
        }
        .onDisappear(perform: MobileOrientationDelegate.leaveLandscape)
    }

    private func close() {
        guard !isClosing else { return }
        if isLandscape {
            isClosing = true
            MobileOrientationDelegate.leaveLandscape()
        } else {
            MobileOrientationDelegate.leaveLandscape()
            dismiss()
        }
    }
}

private struct LandscapeCanvas<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let didReturnToPortrait: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(content: content) }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.host.rootView = content
        controller.didReturnToPortrait = didReturnToPortrait
    }

    final class Controller: UIViewController {
        let host: UIHostingController<Content>
        var didReturnToPortrait: (() -> Void)?
        private var orientationRequest: Task<Void, Never>?
        private var requestedOrientation = false

        init(content: Content) {
            host = UIHostingController(rootView: content)
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(host)
            host.safeAreaRegions = []
            host.view.backgroundColor = .clear
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            let bounds = view.bounds
            let isPortrait = bounds.height > bounds.width
            // Lay out the same landscape canvas synchronously with UIKit's bounds change.
            UIView.performWithoutAnimation {
                host.view.bounds = CGRect(origin: .zero, size: isPortrait
                    ? CGSize(width: bounds.height, height: bounds.width) : bounds.size)
                host.view.center = CGPoint(x: bounds.midX, y: bounds.midY)
                host.view.transform = isPortrait ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
                host.view.layoutIfNeeded()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !requestedOrientation, orientationRequest == nil else { return }
            orientationRequest = Task { [weak self] in
                // Give the presented canvas a frame before starting the native rotation.
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, let self,
                      let scene = self.viewIfLoaded?.window?.windowScene else { return }
                self.requestedOrientation = true
                MobileOrientationDelegate.enterLandscape(in: scene)
            }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            orientationRequest?.cancel()
            orientationRequest = nil
        }

        override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            guard size.height > size.width else { return }
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.didReturnToPortrait?()
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = ProcessInfo.processInfo.environment["PITPULSE_TAB"].flatMap(Int.init) ?? 0
    @State private var showLive = ProcessInfo.processInfo.environment["PITPULSE_OPEN_LIVE"] == "1"
    @State private var showCalendar = false
    @State private var opensLiveAfterSheet = false
    @State private var returningFromBackground = false
    @State private var dashboardLandings: [DashboardTab: UUID] = [:]
    @State private var titleChange: DashboardTitleChange?
    @Namespace private var liveTransition

    private static let tabIcons = Dictionary(uniqueKeysWithValues: DashboardTab.allCases.compactMap { tab -> (DashboardTab, UIImage)? in
        let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        guard let glyph = UIImage(systemName: tab.symbol, withConfiguration: configuration) else { return nil }
        let canvas = CGSize(width: 28, height: 25)
        let origin = CGPoint(x: (canvas.width - glyph.size.width) / 2, y: (canvas.height - glyph.size.height) / 2)
        // The tab bar otherwise applies its own symbol configuration.
        let icon = UIGraphicsImageRenderer(size: canvas).image { _ in
            glyph.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: origin)
        }
        return (tab, icon.withRenderingMode(.alwaysTemplate))
    })
    var body: some View {
        TabView(selection: Binding(get: { selection }, set: { selectTab($0) })) {
            ForEach(DashboardTab.allCases) { tab in
                DashboardScreen(tab: tab, fromHome: dashboardLandings[tab] != nil, header: header(for: tab)) { destination in
                    dashboardLandings[destination] = UUID()
                    selectTab(destination.rawValue)
                }
                    .id(dashboardLandings[tab])
                    .environment(\.pulseEnglishPresentation, tab.usesEnglishPresentation)
                    .environment(\.locale, tab.usesEnglishPresentation ? .pulseEnglish : .autoupdatingCurrent)
                    .tabItem {
                        if let icon = Self.tabIcons[tab] {
                            Image(uiImage: icon).accessibilityLabel(tab.title)
                        } else {
                            Image(systemName: tab.symbol).accessibilityLabel(tab.title)
                        }
                    }
                    .tag(tab.rawValue)
            }
        }
        .tint(PulseStyle.red)
        .liveBottomAccessory(isEnabled: model.hasActiveLive) {
            Group {
                Button {
                    model.startLive()
                    showLive = true
                } label: { LiveMiniBar() }
                    .accessibilityIdentifier("live.open")
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "live-player", in: liveTransition)
            }
        }
        .task(id: titleChange?.start) {
            guard let change = titleChange else { return }
            try? await Task.sleep(for: .seconds(0.43))
            if !Task.isCancelled, titleChange?.start == change.start { titleChange = nil }
        }
        .background {
            LiveNoticePresenter(notice: model.liveNotice, open: openLiveNotice, close: { model.liveNotice = nil })
                .frame(width: 0, height: 0)
        }
        .task(id: model.liveNotice) {
            guard let notice = model.liveNotice else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled, model.liveNotice == notice { model.liveNotice = nil }
        }
        .sheet(isPresented: $model.settingsPresented, onDismiss: openLiveAfterSheet) { SettingsScreen() }
        .sheet(isPresented: $showCalendar, onDismiss: openLiveAfterSheet) { CalendarScreen() }
        .fullScreenCover(isPresented: $showLive, onDismiss: MobileOrientationDelegate.endLiveRotation) {
            LiveScreen(onClose: { showLive = false })
                .pulseNavigationZoom("live-player", in: liveTransition)
        }
        .task(id: model.dataContext) {
            #if DEBUG
            if ProcessInfo.processInfo.environment["PITPULSE_OPEN_SETTINGS"] == "1" {
                model.settingsPresented = true
            }
            #endif
            model.startLive()
            async let roster: Void = model.loadF1Roster()
            async let liveCalendar: Void = model.loadCurrentSeasonLiveCalendar()
            await model.loadCalendar()
            model.updateScheduledLiveSession()
            await model.loadWidgetHighlights()
            _ = await (roster, liveCalendar)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                model.updateScheduledLiveSession()
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                returningFromBackground = true
                model.refreshLiveActivityWhenLeavingForeground()
            } else if phase == .active {
                if returningFromBackground {
                    returningFromBackground = false
                    model.refreshLive()
                } else {
                    model.startLive()
                }
                Task {
                    async let liveCalendar: Void = model.loadCurrentSeasonLiveCalendar()
                    await model.loadCalendar(force: true)
                    model.updateScheduledLiveSession()
                    await model.loadWidgetHighlights()
                    await liveCalendar
                }
            }
        }
        .onOpenURL { url in
            if url.host == "live" {
                if !showLive && !model.liveConnecting { model.refreshLive() }
                showLive = true
            }
            if url.host == "calendar" {
                showLive = false
                showCalendar = true
            }
        }
    }

    private func selectTab(_ destination: Int) {
        guard destination != selection, DashboardTab(rawValue: destination) != nil else { return }
        let now = Date.now
        let outgoing = titleChange.flatMap { now.timeIntervalSince($0.start) < 0.13 ? $0.outgoing : nil }
            ?? DashboardTab(rawValue: selection)?.headerTitle
        titleChange = reduceMotion ? nil : outgoing.map { DashboardTitleChange(outgoing: $0, start: now) }
        if !reduceMotion, DashboardTab(rawValue: destination)?.usesEnglishPresentation == true,
           DashboardTab(rawValue: selection)?.usesEnglishPresentation == true {
            withAnimation(.easeInOut(duration: 0.22)) { selection = destination }
        } else {
            selection = destination
        }
    }

    private func header(for tab: DashboardTab) -> some View {
        DashboardHeader(title: tab.headerTitle, change: selection == tab.rawValue ? titleChange : nil)
            .background(PulseStyle.background)
    }

    private func openLiveNotice(_ notice: LiveNotice) {
        model.liveNotice = nil
        guard model.availableLiveSeries.contains(notice.series) else { return }
        model.selectLiveSeries(notice.series)
        if model.settingsPresented || showCalendar {
            opensLiveAfterSheet = true
            model.settingsPresented = false
            showCalendar = false
        } else {
            showLive = true
        }
    }

    private func openLiveAfterSheet() {
        guard opensLiveAfterSheet else { return }
        opensLiveAfterSheet = false
        showLive = true
    }
}

private struct LiveNoticeBanner: View {
    let notice: LiveNotice
    let open: (LiveNotice) -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button { open(notice) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(PulseStyle.red)
                        .accessibilityHidden(true)
                    Text(notice.text)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .accessibilityHint("Open this race")
            .accessibilityIdentifier("live.notice.open")
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Dismiss race alert")
        }
        .buttonStyle(.plain)
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
        .dashboardPanel(.regularMaterial)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .padding(.vertical, 8)
        .pulseReveal()
    }
}

private struct LiveNoticePresenter: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let notice: LiveNotice?
    let open: (LiveNotice) -> Void
    let close: () -> Void

    func makeUIView(context: Context) -> Anchor { Anchor() }

    func updateUIView(_ view: Anchor, context: Context) {
        view.banner = notice.map { LiveNoticeBanner(notice: $0, open: open, close: close) }
        view.appearance = colorScheme == .dark ? .dark : .light
        view.updateBanner()
    }

    static func dismantleUIView(_ uiView: Anchor, coordinator: ()) {
        uiView.banner = nil
        uiView.updateBanner()
    }

    final class Anchor: UIView {
        var banner: LiveNoticeBanner?
        var appearance: UIUserInterfaceStyle = .unspecified
        private var bannerWindow: BannerWindow?
        private weak var scene: UIWindowScene?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // A full-screen cover can temporarily detach the underlying view.
            if let windowScene = window?.windowScene { scene = windowScene }
            updateBanner()
        }

        func updateBanner() {
            guard let banner, let scene else {
                guard let window = bannerWindow else { return }
                bannerWindow = nil
                window.isUserInteractionEnabled = false
                UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.16) {
                    window.host.view.alpha = 0
                } completion: { _ in
                    window.isHidden = true
                }
                return
            }

            if let bannerWindow, bannerWindow.windowScene === scene {
                bannerWindow.host.rootView = banner
                bannerWindow.overrideUserInterfaceStyle = appearance
            } else {
                let window = BannerWindow(scene: scene, banner: banner)
                window.overrideUserInterfaceStyle = appearance
                bannerWindow = window
                window.isHidden = false
            }
        }
    }

    // A non-key window keeps the notice above sheets without moving any screen's content.
    private final class BannerWindow: UIWindow {
        let host: UIHostingController<LiveNoticeBanner>

        init(scene: UIWindowScene, banner: LiveNoticeBanner) {
            host = UIHostingController(rootView: banner)
            super.init(windowScene: scene)
            windowLevel = .normal + 1
            backgroundColor = .clear

            let controller = UIViewController()
            controller.view.backgroundColor = .clear
            rootViewController = controller
            controller.addChild(host)
            host.sizingOptions = .intrinsicContentSize
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(host.view)

            let width = host.view.widthAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.widthAnchor, constant: -32)
            width.priority = .defaultHigh
            NSLayoutConstraint.activate([
                width,
                host.view.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
                host.view.centerXAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.centerXAnchor),
                host.view.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor)
            ])
            host.didMove(toParent: controller)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard host.view.bounds.contains(convert(point, to: host.view)) else { return nil }
            return super.hitTest(point, with: event)
        }
    }
}

private struct DashboardTitleChange {
    let outgoing: String
    let start: Date
}

private struct DashboardHeader: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var titleSize = 22.0
    let title: String
    let change: DashboardTitleChange?

    var body: some View {
        HStack(spacing: 10) {
            MotorsportImages.image(named: MotorsportAssetName.brandLogoName)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .scaleEffect(1.65)
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                if let change, change.outgoing != title, !reduceMotion, !typeSize.isAccessibilitySize {
                    TimelineView(.animation) { context in
                        let elapsed = context.date.timeIntervalSince(change.start)
                        ZStack(alignment: .leading) {
                            letters(change.outgoing, elapsed: elapsed, entering: false)
                            letters(title, elapsed: elapsed, entering: true)
                        }
                        .clipped()
                    }
                } else if !typeSize.isAccessibilitySize {
                    letters(title, elapsed: 1, entering: true)
                }
                Text(title).lineLimit(1).minimumScaleFactor(0.55)
            }
            .font(.system(size: titleSize, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("dashboard.title")

            Button { model.settingsPresented = true } label: {
                Image(systemName: "gauge.open.with.lines.needle.67percent.and.arrowtriangle")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Open PitPulse settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func letters(_ text: String, elapsed: TimeInterval, entering: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, letter in
                let delay = Double(index) * 0.011 + (entering ? 0.095 : 0)
                let progress = min(max((elapsed - delay) / 0.18, 0), 1)
                let eased = entering ? 1 - pow(1 - progress, 3) : progress * progress
                Text(String(letter))
                    .fixedSize()
                    .offset(y: titleSize * (entering ? eased - 1 : eased))
                    .opacity(entering ? eased : 1 - eased)
            }
        }
        .fixedSize()
    }
}

struct LiveMiniBar: View {
    @EnvironmentObject private var model: MobileModel

    var body: some View {
        let snapshot = model.liveSnapshot
        HStack(spacing: 10) {
            MotorsportImages.image(named: MotorsportAssetName.seriesLogoName(isWec: model.series == .wec))
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 62, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let countryCode = model.liveCountryCode {
                        FlagBadge(countryCode: countryCode, width: 17)
                            .accessibilityHidden(true)
                    }
                    Text(model.liveMeetingName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                LiveClockTimeline(snapshot: snapshot, scheduledSession: model.liveScheduleForDisplay) { progress in
                    Text([model.liveSessionName, progress].compactMap { $0 }.joined(separator: " · "))
                }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Text(model.liveEntries[model.series]?.sourceMode == .replay ? "Replay" : "LIVE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(snapshot.sourceStatus == .connected ? PulseStyle.red : .secondary)
                .lineLimit(1)
            Image(systemName: "chevron.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open live timing")
    }
}

enum PulseStyle {
    static let cardShape = RoundedRectangle(cornerRadius: 26, style: .continuous)
    static let insetShape = ConcentricRectangle(corners: .concentric(minimum: .fixed(12)), isUniform: true)
    static let red = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.98, green: 0.25, blue: 0.23, alpha: 1) : UIColor(red: 0.78, green: 0.08, blue: 0.07, alpha: 1) })
    static let background = WebDashboardStyle.homeBackground
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.060, green: 0.081, blue: 0.117, alpha: 1) : .white
    })
}

struct PulseSettingsButton: View {
    @EnvironmentObject private var model: MobileModel
    var body: some View {
        Button { model.settingsPresented = true } label: {
            MotorsportImages.image(named: MotorsportAssetName.brandLogoName).resizable().scaledToFit().frame(width: 30, height: 30)
        }.accessibilityLabel("Open PitPulse settings")
    }
}

struct PulseCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseStyle.surface, in: PulseStyle.cardShape)
            .containerShape(PulseStyle.cardShape)
            .pulseReveal()
    }
}

struct PulseCardDestination<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        PulseCard {
            HStack(spacing: 12) {
                content.frame(maxWidth: .infinity, alignment: .leading)
                PulseChevron()
            }
        }.contentShape(PulseStyle.cardShape)
            .accessibilityElement(children: .combine)
    }
}

struct PulseChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

struct AssetImage: View {
    let name: String
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        if let image = DashboardArt.image(named: name, traits: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)) {
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

private struct PulseNavigationZoom<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: ID
    let namespace: Namespace.ID

    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        }
    }
}

extension View {
    func pulseNavigationZoom<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        modifier(PulseNavigationZoom(id: id, namespace: namespace))
    }
}

struct PulseSectionPicker<Selection: Hashable>: View {
    let sections: [(Selection, String)]
    @Binding var selection: Selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(sections, id: \.0) { item in
                let isSelected = selection == item.0
                Button {
                    selection = item.0
                } label: {
                    Text(item.1)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? PulseStyle.red : .secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background {
                            if isSelected {
                                Capsule().fill(PulseStyle.red.opacity(0.10))
                                    .matchedGeometryEffect(id: "selection", in: indicator)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("section.\(item.1)")
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0), value: selection)
        .padding(.horizontal, 4)
        .background {
            Capsule().fill(.primary.opacity(0.05)).padding(.vertical, 5)
        }
    }
}


struct LiveSeriesPicker: View {
    let series: [LiveSeries]
    let selected: LiveSeries
    let select: (LiveSeries) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(series) { entry in
                Button { select(entry) } label: {
                    Text(entry.shortTitle)
                        .font(.caption2.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .liveFilledCapsule(isSelected: entry == selected)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.title)
                .accessibilityAddTraits(entry == selected ? .isSelected : [])
                .accessibilityIdentifier("live.series.\(entry.rawValue)")
            }
        }
    }
}

extension View {
    func liveFilledCapsule(isSelected: Bool = true) -> some View {
        modifier(LiveFilledCapsule(isSelected: isSelected))
    }
}

private struct LiveFilledCapsule: ViewModifier {
    @Environment(\.colorScheme) private var appearance
    let isSelected: Bool

    func body(content: Content) -> some View {
        let dark = appearance == .dark
        content
            .foregroundStyle(isSelected ? (dark ? Color.black : .white) : .secondary)
            .background(isSelected ? (dark ? Color.white : .black) : .clear, in: .capsule)
    }
}

extension EnvironmentValues {
    @Entry var pulseEnglishPresentation = true
}

extension View {
    func pulseReveal() -> some View { modifier(PulseReveal()) }

    func pulseChart() -> some View { modifier(PulseReveal(isChart: true)) }

    func pulseNumber<Value: Equatable>(_ value: Value) -> some View {
        modifier(PulseNumberMotion(value: value))
    }
}

private struct PulseReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pulseEnglishPresentation) private var enabled
    @State private var revealed = false
    var isChart = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled && !reduceMotion {
            Group {
                if isChart {
                    content.scaleEffect(x: revealed ? 1 : 0.93, y: 1, anchor: .leading)
                } else {
                    content.offset(y: revealed ? 0 : 7)
                }
            }
            .opacity(revealed ? 1 : 0)
            .transition(.opacity)
            .onAppear {
                withAnimation(.easeOut(duration: isChart ? 0.46 : 0.25)) { revealed = true }
            }
            .onDisappear { revealed = false }
        } else {
            content
        }
    }
}

private struct PulseNumberMotion<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pulseEnglishPresentation) private var enabled
    let value: Value

    func body(content: Content) -> some View {
        content
            .contentTransition(enabled && !reduceMotion ? .numericText() : .identity)
            .animation(enabled && !reduceMotion ? .easeOut(duration: 0.2) : nil, value: value)
    }
}

struct PulseSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var rows: Int = 3
    var label = "Loading"
    var chart = false

    var body: some View {
        VStack(spacing: 10) {
            if chart {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach([22.0, 44, 33, 56, 41, 70, 54, 63], id: \.self) { height in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(maxWidth: .infinity)
                            .frame(height: height)
                    }
                }
                .frame(height: 78, alignment: .bottom)
            } else {
                ForEach(0..<rows, id: \.self) { index in
                    HStack(spacing: 10) {
                        Circle().fill(.quaternary).frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(.quaternary).frame(width: index.isMultiple(of: 2) ? 94 : 74, height: 8)
                            Capsule().fill(.quaternary).frame(width: 53, height: 6)
                        }
                        Spacer(minLength: 2)
                        Capsule().fill(.quaternary).frame(width: 29, height: 8)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebDashboardStyle.homePanel, in: PulseStyle.cardShape)
        .opacity(pulse && !reduceMotion ? 0.55 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = !reduceMotion }
        .onDisappear { pulse = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .transition(.opacity)
    }
}

extension IslandContentMode {
    var englishTitle: String {
        switch self {
        case .overview: "Race Overview"
        case .battle: "Driver Battle"
        case .favorite: "Favorite Driver"
        case .positionChanges: "Position Changes"
        }
    }
}

extension LiveSnapshot {
    var englishStatus: String {
        switch (sourceMode, sourceStatus) {
        case (.replay, .connected): "Replay"
        case (.replay, .stale): "Replay · Reconnecting"
        case (.replay, .disconnected): "Replay"
        case (.live, .connected): updatedAt == nil ? "Waiting for data" : "LIVE"
        case (.live, .stale): "Reconnecting"
        case (.live, .disconnected): "LIVE"
        }
    }

    var englishSessionState: String {
        switch sessionStatus?.lowercased() {
        case "started", "green", "inprogress", "running", "live": trackCondition == .red ? "Red Flag" : "In Progress"
        case "finished", "finalised", "finalized", "ends": "Finished"
        case "aborted": "Aborted"
        case "inactive": "Awaiting Start"
        default: "Unknown Status"
        }
    }

    var englishLap: String { lapCount == nil ? "—" : lapLabel }
}

extension LiveTrackCondition {
    var englishLabel: String {
        switch self {
        case .clear: "Green flag · Track clear"
        case .yellow: "Yellow flag"
        case .fullCourseYellow: "Full-course yellow"
        case .safetyCar: "Safety car"
        case .safetyCarEnding: "Safety car in this lap"
        case .red: "Red flag · Session suspended"
        case .virtualSafetyCar: "Virtual safety car"
        case .virtualSafetyCarEnding: "Virtual safety car ending"
        case .unknown: "Unknown track status"
        }
    }
}

extension String {
    var pulseEnglishError: String {
        let translations = [
            "服务器地址无效。": "Invalid server address.",
            "服务器地址无效": "Invalid server address",
            "服务器响应格式无效。": "Invalid server response.",
            "无法连接服务器。": "Could not connect to the server.",
            "连接服务器超时。": "The server connection timed out.",
            "Token 无效或缺失。": "The access token is missing or invalid.",
            "服务器数据无法解析，可能是不兼容的版本。": "The server response could not be read.",
            "当前服务器暂无 F1 车手数据，请检查服务地址。": "The server has no F1 drivers. Check the server address."
        ]
        if let translation = translations[self] { return translation }
        if contains("HTTP"), let code = split(whereSeparator: { !$0.isASCII || !$0.isNumber }).last {
            return "Server returned HTTP \(code)."
        }
        return unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } ? "The request could not be completed." : self
    }
}

struct PulseNumber: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(verbatim: value).pulseNumber(value)
    }
}

extension View {
    func pulseSwap<Value: Equatable>(_ value: Value) -> some View {
        modifier(PulseSwap(value: value))
    }
}

private struct PulseSwap<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pulseEnglishPresentation) private var enabled
    let value: Value

    func body(content: Content) -> some View {
        content.animation(enabled && !reduceMotion ? .easeInOut(duration: 0.22) : nil, value: value)
    }
}

extension Locale {
    static let pulseEnglish = Locale(identifier: "en_US")
}

extension LiveSnapshot {
    var englishLastUpdated: String? {
        updatedAt.flatMap(RFC3339.parse)?.formatted(.dateTime.hour().minute().locale(.pulseEnglish))
    }
}
