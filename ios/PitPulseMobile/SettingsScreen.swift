import SharedComponents
import SwiftUI
import SceneKit
import SharedData

struct SettingsScreen: View {
    @EnvironmentObject private var model: MobileModel
    @State private var serverConfigurationPresented = false
    @State private var serverReachable: Bool?
    @State private var widgetPreviewPresented = false
    @State private var islandPreviewPresented = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mobileAppearance") private var appearance = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image("logo-foreground.png").resizable().scaledToFit().frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 4) { Text("PitPulse").font(.title2.bold()); Text("MOTORSPORT LIVE & DATA").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary) }
                    }
                }
                Section("服务器") {
                    HStack(spacing: 8) {
                        if let url = model.serverURL {
                            Link(model.serverText, destination: url).lineLimit(1).truncationMode(.middle)
                        } else {
                            Text("未配置服务器").foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                        Image(systemName: serverReachable == true ? "checkmark.circle.fill" : serverReachable == false ? "xmark.circle.fill" : "circle.dotted")
                            .font(.title2)
                            .foregroundStyle(serverReachable == true ? Color.green : serverReachable == false ? Color.red : Color.secondary)
                            .accessibilityLabel(serverReachable == true ? "服务器可用" : serverReachable == false ? "服务器不可用" : "正在检查服务器")

                        Button { serverConfigurationPresented = true } label: {
                            Image(systemName: "square.and.pencil").font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("配置服务器")
                    }
                    .listRowSeparator(.hidden)
                }

                Section("偏好设置") {
                    Picker("赛季", selection: $model.season) {
                        ForEach(2023...2027, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }

                    Picker("主题", selection: $appearance) {
                        Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                    }.pickerStyle(.menu)

                    Picker("收藏车手", selection: $model.favoriteDriverID) {
                        Text("未选择").tag(String?.none)
                        ForEach(model.driverRoster) { driver in
                            Text(driver.driverName).tag(String?.some(driver.id))
                        }
                    }
                    if model.driverRoster.isEmpty {
                        Text(model.rosterLoadError ?? "正在加载车手…").font(.caption).foregroundStyle(.secondary)
                        Button("重新加载车手") { Task { await model.loadF1Roster(force: true) } }
                    }
                }
                Section("组件") {
                    Button {
                        islandPreviewPresented = true
                    } label: {
                        HStack {
                            Text("灵动岛显示")
                            Spacer()
                            Text(model.islandMode.title).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel("灵动岛显示：\(model.islandMode.title)")
                    #if DEBUG
                    Button { widgetPreviewPresented = true } label: {
                        HStack {
                            Text("桌面组件预览")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                    #endif
                }

                Section("关于") {
                    LabeledContent("版本", value: "0.1.0")
                    LabeledContent("数据层", value: model.hasToken ? "SharedData · Token 已保存" : "SharedData")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .formStyle(.grouped)
            .tint(PulseStyle.red)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭设置")
                }
            }
            .task(id: model.dataContext) {
                let context = model.dataContext
                serverReachable = nil
                if let url = model.serverURL {
                    do {
                        let health = try await APIClient(baseURL: url).health(token: model.currentToken)
                        guard !Task.isCancelled, context == model.dataContext else { return }
                        serverReachable = health.database && health.status == "ok"
                    } catch {
                        guard !Task.isCancelled, context == model.dataContext else { return }
                        serverReachable = false
                    }
                } else { serverReachable = false }
                await model.loadF1Roster()
            }
        }
        // Present from the stable settings root, not a lazily rebuilt Form section.
        .sheet(isPresented: $serverConfigurationPresented) {
            ServerConfigurationSheet().environmentObject(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $islandPreviewPresented) {
            IslandModePreviewSheet()
                .environmentObject(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #if DEBUG
        .sheet(isPresented: $widgetPreviewPresented) {
            NavigationStack { WidgetPreviewGallery() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #endif
    }

 }

private struct ServerConfigurationSheet: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var result: String?
    @State private var testRequest: UUID?
    @State private var isTesting = false
    @FocusState private var focusedField: Field?
    private enum Field { case address, token }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 18) {
                    Text("服务器设置")
                        .font(.title)
                        .foregroundStyle(.primary)

                    Text("连接到你的私人服务器")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                VStack(spacing: 14) {
                    TextField("服务器地址", text: $address)
                        .keyboardType(.URL).textContentType(.URL)
                        .focused($focusedField, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .token }
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    SecureField(model.hasToken ? "Token（留空保留已有令牌）" : "Token（可选）", text: $token)
                        .focused($focusedField, equals: .token)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        focusedField = nil
                        isTesting = true
                        result = nil
                        testRequest = UUID()
                    } label: {
                        Group {
                            if isTesting { ProgressView().frame(maxWidth: .infinity) }
                            else { Text("测试").frame(maxWidth: .infinity) }
                        }.padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("测试当前填写的服务器")
                    .buttonBorderShape(.capsule)

                    Button {
                        if let error = model.saveConnection(address: address, token: token) {
                            result = error
                        } else {
                            token = ""
                            dismiss()
                            Task { await model.loadCalendar(force: true) }
                        }
                    } label: {
                        Text("保存").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonBorderShape(.capsule)

                    if let result {
                        Text(result).font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 480).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .tint(PulseStyle.red)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭服务器配置")
                }
            }
            .onAppear { address = model.serverText }
            .onChange(of: address) { _, _ in invalidateTest() }
            .onChange(of: token) { _, _ in invalidateTest() }
            .task(id: testRequest) {
                guard testRequest != nil else { return }
                do {
                    let server = try ServerAddress(rawValue: address)
                    let typedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    let credential = typedToken.isEmpty ? (server.url == model.serverURL ? model.currentToken : nil) : typedToken
                    let health = try await APIClient(baseURL: server.url).health(token: credential)
                    guard !Task.isCancelled else { return }
                    result = health.database && health.status == "ok" ? "连接成功" : "服务已响应，数据库暂不可用"
                } catch {
                    guard !Task.isCancelled else { return }
                    result = MobileModel.message(for: error)
                }
                isTesting = false
            }
        }
    }

    private func invalidateTest() {
        testRequest = nil
        isTesting = false
        result = nil
    }
}


/// A draft stays local to this sheet. Only Save changes the persisted mode.
private typealias IslandPreviewPage = IslandContentMode

struct IslandModePreviewSheet: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: IslandPreviewPage?
    @State private var displayedMode: IslandPreviewPage?
    @State private var islandExpanded = true
    @State private var previewExpanded = true
    @State private var tuningModel = false
    @State private var modelPose = IslandModelPose()

    private var mode: IslandPreviewPage { selection ?? IslandPreviewPage(rawValue: model.islandMode.rawValue)! }
    private var descriptions: String {
        switch mode {
        case .overview: "比赛进度、赛道旗号与前三名同屏。\n扫一眼头盔和差距，掌握前方局势。"
        case .battle: "收藏车手与前车同屏，看清追击差距。\n在 Live 选择一至两位，跟踪分段与轮胎。"
        case .positionChanges: "领跑者始终在侧，全场超越尽收眼底。\n追踪最前方的名次变化，每次停留至少十秒。"
        case .favorite: "跟住你支持的车手，掌握前后差距。\n分段进度、速度和轮胎，随时看清节奏。"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let stageTop = max(110, geometry.size.height * 0.16)
            ZStack(alignment: .top) {
                Color(uiColor: .systemBackground)
                GeometryReader { background in
                    IslandPhonePreview(state: previewState(displayedMode ?? mode), expanded: islandExpanded, pose: modelPose) {
                        guard !islandExpanded, previewExpanded else { return }
                        displayedMode = mode
                        islandExpanded = true
                    }
                        .frame(width: background.size.width, height: background.size.height - stageTop)
                        .offset(y: stageTop)
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)


                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(height: 340)
                        .glassEffect(.clear, in: Rectangle())
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.42), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .allowsHitTesting(false)
                VStack(spacing: 22) {
                    HStack {
                        Text("灵动岛显示").font(.headline).frame(maxWidth: .infinity)
                    }
                    #if DEBUG
                    .overlay(alignment: .leading) {
                        Button { tuningModel.toggle() } label: {
                            Image(systemName: "slider.horizontal.3")
                                .frame(width: 44, height: 44)
                                .background(.quaternary, in: Circle())
                        }
                        .accessibilityLabel("调整模型")
                        .accessibilityIdentifier("islandPreview.tuneModel")
                    }
                    #endif
                    .overlay(alignment: .trailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.body.weight(.medium))
                                .frame(width: 44, height: 44)
                                .background(.quaternary, in: Circle())
                        }.accessibilityLabel("关闭灵动岛预览")
                    }
                    Spacer(minLength: 16)
                    VStack(spacing: 12) {
                        VStack(spacing: 10) {
                            Text(mode.title).font(.title2.weight(.medium)).foregroundStyle(.white)
                            Text(descriptions).font(.subheadline).foregroundStyle(.white.opacity(0.82))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }.accessibilityElement(children: .combine)
                        HStack(spacing: 0) {
                            ForEach(IslandPreviewPage.allCases) { candidate in
                                Button { selection = candidate } label: {
                                    Circle().fill(candidate == mode ? Color.white : Color.white.opacity(0.35))
                                        .frame(width: 6, height: 6).frame(width: 14, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(candidate.title)
                                .accessibilityAddTraits(candidate == mode ? [.isSelected] : [])
                            }
                        }
                        Button {
                            model.islandMode = mode
                            dismiss()
                        } label: {
                            Text("使用此模式").font(.body.weight(.medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                        .accessibilityIdentifier("islandPreview.save")
                    }
                    .padding(.bottom, 4)

                }
                .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 16)
                .safeAreaPadding(.bottom)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                guard !tuningModel,
                      abs(value.translation.width) > abs(value.translation.height),
                      abs(value.predictedEndTranslation.width) > 45 else { return }
                changeMode(by: value.translation.width < 0 ? 1 : -1)
            })
            #if DEBUG
            .overlay(alignment: .bottom) {
                if tuningModel {
                    modelTuner
                        .padding(.horizontal, 16).padding(.bottom, 118)
                }
            }
            #endif
            .accessibilityIdentifier("islandPreview.stage")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: changeMode(by: 1)
                case .decrement: changeMode(by: -1)
                @unknown default: break
                }
            }
            .task(id: mode) { await transitionIsland(to: mode) }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())

        .tint(PulseStyle.red)
        .presentationBackground(Color(uiColor: .systemBackground))
        #if DEBUG
        .task {
            if CommandLine.arguments.contains("--island-position-preview") { selection = .positionChanges; return }
            guard CommandLine.arguments.contains("--island-tour") else { return }
            for candidate in [IslandPreviewPage.battle, .favorite, .overview] {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                selection = candidate
            }
        }
        #endif
    }

    private var modelTuner: some View {
        VStack(spacing: 8) {
            HStack {
                Text("调整模型").font(.headline)
                Spacer()
                Button("重置") { modelPose = IslandModelPose() }
                Button { tuningModel = false } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("收起模型调节")
            }
            poseSlider("X 轴角度", value: $modelPose.xAngle, range: -45...45, step: 0.1, suffix: "°")
            poseSlider("Y 轴角度", value: $modelPose.yAngle, range: -60...60, step: 0.1, suffix: "°")
            poseSlider("Z 轴角度", value: $modelPose.zAngle, range: -45...45, step: 0.1, suffix: "°")
            poseSlider("横向位置", value: $modelPose.horizontal, range: -3...3, step: 0.01, suffix: "")
            poseSlider("纵向位置", value: $modelPose.vertical, range: -3...3, step: 0.01, suffix: "")
            poseSlider("机身厚度", value: $modelPose.thickness, range: 0.3...1.1, step: 0.01, suffix: "")
            Text("横向向右为正 · 纵向向下为正；仅本次预览生效")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func poseSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: suffix.isEmpty ? "%.2f%@" : "%.1f%@", value.wrappedValue, suffix))
                    .monospacedDigit()
            }.font(.caption)
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
        }
    }

    private func changeMode(by step: Int) {
        let modes = IslandPreviewPage.allCases
        guard let index = modes.firstIndex(of: mode) else { return }
        selection = modes[min(max(index + step, 0), modes.count - 1)]
    }

    private func transitionIsland(to target: IslandPreviewPage) async {
        if !previewExpanded {
            displayedMode = target
            islandExpanded = false
            return
        }
        guard let displayedMode else {
            self.displayedMode = target
            return
        }
        guard displayedMode != target else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.64)) {
                islandExpanded = true
            }
            return
        }
        if reduceMotion {
            self.displayedMode = target
            islandExpanded = true
            return
        }
        // The texture animator calls back at its actual collapsed endpoint.
        // Rapid selections replace the pending target without a guessed delay.
        islandExpanded = false
    }

    private func previewState(_ mode: IslandPreviewPage) -> PitPulseActivityAttributes.ContentState {
        let sectors: [PitPulseActivityAttributes.Sector] = [
            .init(time: "18.426", segments: [2049, 2049, 2051, 2049], personalFastest: true),
            .init(time: "36.812", segments: [2049, 2048, 2049, 2049]),
            .init(time: nil, segments: [2049, 2049, nil, nil])]
        let max = PitPulseActivityAttributes.Driver(name: "Max VERSTAPPEN", position: 2, asset: "helmet-max_verstappen-2026", gap: "+0.842", interval: "+0.842", speed: 312, tire: "M 18", lastLap: "1:11.482", sectors: sectors)
        let lando = PitPulseActivityAttributes.Driver(name: "Lando NORRIS", position: 1, asset: "helmet-norris-2026", gap: "LEADER", speed: 309, tire: "M 20", sectors: sectors)
        let charles = PitPulseActivityAttributes.Driver(name: "Charles LECLERC", position: 3, asset: "helmet-leclerc-2026", gap: "+4.216")
        return .init(sessionName: "Race", meetingName: "São Paulo Grand Prix",
            statusLabel: "比赛进行中", lapLabel: "L32/71",
            leaderName: "Lando NORRIS", leaderGap: "LEADER",
            challengerName: "Max VERSTAPPEN", challengerGap: "+0.842",
            leaderAsset: "helmet-norris-2026", challengerAsset: "helmet-max_verstappen-2026",
            trackLabel: "绿旗 · 赛道畅通", driverCount: 22,
            presentation: mode.rawValue, favoriteName: "Max VERSTAPPEN",
            favoritePosition: 2, favoriteGap: "+0.842", favoriteGapLabel: "距领先", favoriteAsset: "helmet-max_verstappen-2026", podium: [lando, max, charles], battleDrivers: [lando, max], trackedDriver: max, battleGap: "+0.842", weather: .init(rainfall: false, airTemperature: 24, trackTemperature: 37, visibilityMeters: 10000))
    }
}

private struct IslandModelPose {
    var xAngle = 4.8
    var yAngle = 21.4
    var zAngle = 8.5
    var horizontal = -0.43
    var vertical = 0.17
    var thickness = 0.80

    func apply(to node: SCNNode) {
        node.eulerAngles = SCNVector3(Float(xAngle * .pi / 180), Float(yAngle * .pi / 180), Float(zAngle * .pi / 180))
        node.position = SCNVector3(Float(horizontal), Float(-vertical), 0)
    }
}

/// The screen and chassis share one SceneKit coordinate system and camera.
private struct IslandPhonePreview: UIViewRepresentable {
    let state: PitPulseActivityAttributes.ContentState
    let expanded: Bool
    var pose: IslandModelPose
    var onCollapsed: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator: NSObject {
        var material: SCNMaterial?
        var builtThickness: Double?
        var state: PitPulseActivityAttributes.ContentState?
        var progress: Double = 1
        var start: Double = 1
        var target: Double = 1
        var began: CFTimeInterval = 0
        var link: CADisplayLink?
        var onCollapsed: (@MainActor () -> Void)?
        var timelineBegan = CACurrentMediaTime()
        var lastFrame = -1
        var reduceMotion = false

        func update(state: PitPulseActivityAttributes.ContentState, expanded: Bool, animated: Bool) {
            if self.state?.presentation != state.presentation { timelineBegan = CACurrentMediaTime(); lastFrame = -1 }
            self.state = state
            reduceMotion = !animated
            if link == nil {
                let timer = CADisplayLink(target: self, selector: #selector(tick))
                timer.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
                timer.add(to: .main, forMode: .common)
                link = timer
            }
            let next = expanded ? 1.0 : 0.0
            if !animated {
                progress = next
                target = next
            }
            if next != target {
                start = progress
                target = next
                began = CACurrentMediaTime()
            }
            render()
        }

        @objc func tick() {
            if progress != target {
                let t = min(1, (CACurrentMediaTime() - began) / (target == 0 ? 0.38 : 0.85))
                let eased = target == 0 ? 1 - pow(1 - t, 3) : (t == 1 ? 1 : 1 - exp(-8 * t) * (cos(10 * t) + 0.8 * sin(10 * t)))
                progress = start + (target - start) * eased
                render()
                if t == 1, target == 0 { onCollapsed?() }
            } else {
                let elapsed = CACurrentMediaTime() - timelineBegan
                let fourth = state?.presentation == IslandPreviewPage.positionChanges.rawValue
                let phase = fourth ? PositionChangesPreview.phase(at: elapsed) : elapsed.truncatingRemainder(dividingBy: 5)
                let moving = phase < (fourth ? 1.4 : 0.35)
                let frame = moving ? Int(elapsed * 30) : (fourth ? PositionChangesPreview.event(at: elapsed) : Int(elapsed / 5)) * 10000 + 9999
                if frame != lastFrame { lastFrame = frame; render() }
            }
        }

        func render() {
            guard let state else { return }
            let renderer = ImageRenderer(content: PreviewDisplay(state: state, progress: progress, elapsed: CACurrentMediaTime() - timelineBegan, reduceMotion: reduceMotion))
            renderer.scale = 2
            material?.diffuse.contents = renderer.uiImage
        }
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.link?.invalidate()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onCollapsed = onCollapsed
        if context.coordinator.material != nil, context.coordinator.builtThickness == pose.thickness {
            if let phone = view.scene?.rootNode.childNode(withName: "previewPhone", recursively: false) {
                pose.apply(to: phone)
            }
            context.coordinator.update(state: state, expanded: expanded, animated: !reduceMotion)
            return
        }
        context.coordinator.builtThickness = pose.thickness
        let scene = SCNScene()
        let root = SCNNode()
        root.name = "previewPhone"
        scene.rootNode.addChildNode(root)
        let studio = IslandPreviewTexture.make(width: 1024, height: 512) { context in
            let colors = [UIColor(white: 0.12, alpha: 1).cgColor, UIColor(white: 0.95, alpha: 1).cgColor, UIColor(white: 0.25, alpha: 1).cgColor, UIColor.white.cgColor, UIColor(white: 0.08, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.22, 0.40, 0.62, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1024, y: 150), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        scene.lightingEnvironment.contents = studio
        scene.lightingEnvironment.intensity = 1.5
        let brushedMetal = IslandPreviewTexture.make(width: 256, height: 4096) { context in
            UIColor(white: 0.65, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 4096))
            for row in 0..<4096 {
                let value = 0.63 + 0.025 * (sin(Double(row) * 127.1) * 0.5 + 0.5)
                UIColor(white: value, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: row, width: 256, height: 1))
            }
        }
        let brushedNormal = IslandPreviewTexture.make(width: 128, height: 2048) { context in
            for row in 0..<2048 {
                let grain = sin(Double(row) * 91.7) * 0.10
                UIColor(red: 0.5, green: 0.5 + grain, blue: 1, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: row, width: 128, height: 1))
            }
        }
        func shell(width: CGFloat, height: CGFloat, radius: CGFloat, depth: CGFloat, color: UIColor, z: Float) {
            let path = UIBezierPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerRadius: radius)
            path.flatness = 0.001
            let shape = SCNShape(path: path, extrusionDepth: depth)
            shape.chamferRadius = 0.025
            shape.firstMaterial?.diffuse.contents = color
            shape.firstMaterial?.lightingModel = .physicallyBased
            if depth > 0.1 {
                shape.firstMaterial?.diffuse.contents = brushedMetal
                shape.firstMaterial?.normal.contents = brushedNormal
                shape.firstMaterial?.normal.intensity = 0.65
            }
            shape.firstMaterial?.metalness.contents = 0.9
            shape.firstMaterial?.roughness.contents = depth > 0.1 ? 0.34 : 0.22
            let node = SCNNode(geometry: shape)
            node.position.z = z
            root.addChildNode(node)
        }
        // Add thickness behind the fixed front face; keep screen alignment intact.
        let bodyDepth = CGFloat(pose.thickness)
        let bodyCenterZ: Float = 0.07 - Float(bodyDepth) / 2
        let sideKeyZ = bodyCenterZ + 0.04
        shell(width: 4.16, height: 8.88, radius: 0.57, depth: bodyDepth,
              color: UIColor(white: 0.34, alpha: 1), z: bodyCenterZ)
        // A narrow polished front chamfer catches the studio strip separately
        // from the rougher brushed rail; both are actual extruded surfaces.
        shell(width: 4.17, height: 8.89, radius: 0.575, depth: 0.045,
              color: UIColor(white: 0.82, alpha: 1), z: 0.10)
        shell(width: 4.1, height: 8.82, radius: 0.55, depth: 0.025, color: .black, z: 0.145)
        // Flush insulating band across the rail above the mute key.
        let antenna = SCNPlane(width: bodyDepth - 0.04, height: 0.045)
        antenna.cornerRadius = 0.012
        antenna.firstMaterial?.diffuse.contents = UIColor(white: 0.30, alpha: 1)
        antenna.firstMaterial?.lightingModel = .constant
        let antennaNode = SCNNode(geometry: antenna)
        antennaNode.eulerAngles.y = -.pi / 2
        antennaNode.position = SCNVector3(-2.083, 3.10, bodyCenterZ)
        root.addChildNode(antennaNode)
        // Recessed dark gasket plus a rounded metal cap, seated in the side rail.
        for (y, height): (Float, CGFloat) in [(2.7, 0.25), (1.85, 0.56), (0.95, 0.56)] {
            // The gasket needs its own capsule outline: a thin SCNBox clamps
            // chamferRadius to its thickness and leaves square-looking ends.
            let socketOutline = UIBezierPath(roundedRect: CGRect(x: -0.0775, y: -(height + 0.035) / 2,
                width: 0.155, height: height + 0.035), cornerRadius: 0.0775)
            socketOutline.flatness = 0.001
            let socket = SCNShape(path: socketOutline, extrusionDepth: 0.012)
            socket.chamferRadius = 0.004
            socket.firstMaterial?.diffuse.contents = UIColor(white: 0.10, alpha: 1)
            let recess = SCNNode(geometry: socket)
            recess.eulerAngles.y = -.pi / 2
            recess.position = SCNVector3(-2.085, y, sideKeyZ)
            root.addChildNode(recess)
            let outline = UIBezierPath(roundedRect: CGRect(x: -0.0625, y: -height / 2, width: 0.125, height: height), cornerRadius: 0.06)
            outline.flatness = 0.001
            let button = SCNShape(path: outline, extrusionDepth: 0.025)
            button.chamferRadius = 0.008
            let metal = SCNMaterial()
            metal.lightingModel = .physicallyBased
            metal.diffuse.contents = brushedMetal
            metal.metalness.contents = 0.85
            metal.roughness.contents = 0.3
            metal.normal.contents = brushedNormal
            metal.normal.intensity = 0.3
            button.firstMaterial = metal
            let node = SCNNode(geometry: button)
            node.eulerAngles.y = -.pi / 2
            node.position = SCNVector3(-2.105, y, sideKeyZ)
            root.addChildNode(node)
        }
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 700
        key.position = SCNVector3(-5, 5, 6)
        scene.rootNode.addChildNode(key)
        // Double the black inset from 0.04 to 0.08 on each edge.
        let screenInset: CGFloat = 0.08
        let screen = SCNPlane(width: 4.1 - 2 * screenInset, height: 8.82 - 2 * screenInset)
        // Restore the original screen corner; the rolled edge is a separate mesh.
        screen.cornerRadius = 0.50
        screen.cornerSegmentCount = 48
        context.coordinator.material = screen.firstMaterial
        context.coordinator.update(state: state, expanded: expanded, animated: !reduceMotion)
        screen.firstMaterial?.lightingModel = .constant
        let display = SCNNode(geometry: screen)
        display.position.z = 0.183
        root.addChildNode(display)
        // A quarter-round cross-section bridges black bezel and display.
        // This changes the edge profile, not the four screen corner radii.
        var rimVertices: [SCNVector3] = []
        var rimNormals: [SCNVector3] = []
        var rimIndices: [Int32] = []
        let arcSteps = 16
        let profileSteps = 12
        let perimeterCount = 4 * (arcSteps + 1)
        for level in 0...profileSteps {
            let angle = Double(level) / Double(profileSteps) * .pi / 2
            let inset = 0.08 * (1 - cos(angle))
            let z = 0.145 + 0.038 * sin(angle)
            let radius = 0.55 - 0.05 * (inset / 0.08)
            let halfWidth = 2.05 - inset
            let halfHeight = 4.41 - inset
            for corner in 0..<4 {
                let sx = corner == 0 || corner == 3 ? 1.0 : -1.0
                let sy = corner < 2 ? 1.0 : -1.0
                for step in 0...arcSteps {
                    let a = Double(corner) * .pi / 2 + Double(step) / Double(arcSteps) * .pi / 2
                    let nx = cos(a), ny = sin(a)
                    rimVertices.append(SCNVector3(Float(sx * (halfWidth - radius) + radius * nx),
                        Float(sy * (halfHeight - radius) + radius * ny), Float(z)))
                    let lateral = 0.038 * cos(angle)
                    let forward = 0.08 * sin(angle)
                    let magnitude = sqrt(lateral * lateral + forward * forward)
                    rimNormals.append(SCNVector3(Float(nx * lateral / magnitude), Float(ny * lateral / magnitude), Float(forward / magnitude)))
                }
            }
        }
        for level in 0..<profileSteps {
            for point in 0..<perimeterCount {
                let next = (point + 1) % perimeterCount
                let a = Int32(level * perimeterCount + point)
                let b = Int32(level * perimeterCount + next)
                let c = Int32((level + 1) * perimeterCount + point)
                let d = Int32((level + 1) * perimeterCount + next)
                rimIndices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        let rim = SCNGeometry(sources: [SCNGeometrySource(vertices: rimVertices), SCNGeometrySource(normals: rimNormals)],
            elements: [SCNGeometryElement(indices: rimIndices, primitiveType: .triangles)])
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = UIColor(white: 0.018, alpha: 1)
        glass.roughness.contents = 0.18
        rim.firstMaterial = glass
        root.addChildNode(SCNNode(geometry: rim))
        let receiver = SCNPlane(width: 0.52, height: 0.038)
        receiver.cornerRadius = 0.019
        receiver.cornerSegmentCount = 12
        receiver.firstMaterial?.lightingModel = .constant
        receiver.firstMaterial?.diffuse.contents = IslandPreviewTexture.make(width: 208, height: 16) { context in
            UIColor(white: 0.15, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 208, height: 16))
            UIColor(white: 0.40, alpha: 1).setFill()
            for x in stride(from: 4, to: 208, by: 8) {
                context.fillEllipse(in: CGRect(x: x, y: 5, width: 3, height: 6))
            }
        }
        let receiverNode = SCNNode(geometry: receiver)
        receiverNode.position = SCNVector3(0, 4.37, 0.195)
        root.addChildNode(receiverNode)
        pose.apply(to: root)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 42
        camera.position = SCNVector3(-1.08, 0.7, 9.8)
        #if DEBUG
        if CommandLine.arguments.contains("--island-device-overview") {
            camera.position = SCNVector3(0, 0, 18)
        }
        #endif
        scene.rootNode.addChildNode(camera)
        view.scene = scene
        view.pointOfView = camera
    }
}

private struct PreviewDisplay: View {
    let state: PitPulseActivityAttributes.ContentState
    let progress: Double
    let elapsed: Double
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .top) {
            // Keep the whole wallpaper visibly lighter than the black island,
            // including behind the camera and expanded activity.
            Color(red: 0.25, green: 0.13, blue: 0.145)
            // A complete home screen exists underneath the activity. Its top
            // inset reserves the fixed camera capsule, not the expanded island.
            VStack(spacing: 32) {
                ForEach(0..<6) { _ in iconRow(count: 4) }
            }.padding(.top, 80)
            VStack {
                Spacer()
                iconRow(count: 4)
                    .padding(.horizontal, 16).padding(.vertical, 18)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .padding(.bottom, 28)
            }
            Capsule().fill(.black).frame(width: 125, height: 30).padding(.top, 12)
            IslandOverlay(state: state, progress: progress, elapsed: elapsed, reduceMotion: reduceMotion)
                .frame(width: 380, height: 240, alignment: .top).padding(.top, 12)
        }
        .frame(width: 402, height: 874).clipped()
        .environment(\.colorScheme, .dark)
    }

    private func iconRow(count: Int) -> some View {
        HStack(spacing: 22) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.white.opacity(0.12)).frame(width: 64, height: 64)
            }
        }
    }

}

/// Native antialiased shape and content share one plane. Only the container's
/// bounds morph; text and helmets never undergo a nonuniform scale animation.
private struct IslandOverlay: View {
    let state: PitPulseActivityAttributes.ContentState
    let progress: Double
    let elapsed: Double
    let reduceMotion: Bool
    private var sample: IslandPreviewSample { IslandPreviewSample(state: state, elapsed: elapsed, reduceMotion: reduceMotion) }

    private var expandedHeight: CGFloat {
        if state.presentation == IslandPreviewPage.positionChanges.rawValue { return 205 }
        return switch state.presentation.flatMap(IslandContentMode.init(rawValue:)) ?? .overview {
        case .overview: 205
        case .battle: 220
        case .favorite: 235
        case .positionChanges: 205
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            IslandLiquidSilhouette(progress: progress, expandedHeight: expandedHeight)
                .frame(width: 380, height: 240, alignment: .top)
            HStack {
                Text(state.compactLeadingText).font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 125)
                Text(state.compactTrailingText).font(.system(size: 10, weight: .bold)).monospacedDigit()
            }
            .padding(.horizontal, 12).frame(width: 240, height: 36)
            .opacity(max(0, 1 - progress * 4))
            expandedContent
            .padding(18).frame(width: 380, height: expandedHeight)
            .offset(y: -76 * (1 - progress))
            .scaleEffect(0.82 + 0.18 * progress, anchor: .top)
            .opacity(min(1, max(0, (progress - 0.22) / 0.78)))
            .blur(radius: 7 * (1 - min(1, max(0, progress))))
            .mask(contentMask)
        }
        .environment(\.colorScheme, .dark)
    }
    private var contentMask: some View {
        let width: CGFloat = 240 + 140 * progress
        let height: CGFloat = 36 + (expandedHeight - 36) * progress
        return RoundedRectangle(cornerRadius: IslandPreviewGeometry.expandedRadius, style: .continuous)
            .frame(width: width, height: height).frame(maxHeight: .infinity, alignment: .top)
    }
    private var expandedContent: some View {
        VStack(spacing: 10) {
            HStack {
                Text(state.meetingName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if state.isStale { ActivityStatus(state: state, expired: false) }
                else { Text(state.sessionName.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if state.presentation == IslandPreviewPage.positionChanges.rawValue {
                PositionChangesPreview(elapsed: elapsed, reduceMotion: reduceMotion)
            } else {
                ActivityPayloadView(state: sample.state)
                    .environment(\.activityPreviewNumbers, sample.numbers)
            }
            Spacer(minLength: 0)
            if state.presentation != IslandContentMode.overview.rawValue && state.presentation != IslandPreviewPage.positionChanges.rawValue {
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill").foregroundStyle(state.trackColor)
                    Text(state.trackLabel ?? "等待赛道状态").lineLimit(1)
                    Spacer()
                    ActivityNumberText(sample.state.lapLabel).monospacedDigit().environment(\.activityPreviewNumbers, sample.numbers)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

}

/// One continuous surface anchored to the camera; content never stretches per axis.
private struct IslandLiquidSilhouette: View {
    let progress: Double
    let expandedHeight: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: 18 + 26 * progress, style: .continuous)
            .fill(.black)
            .frame(width: 240 + 140 * progress, height: 36 + (expandedHeight - 36) * progress)
            .frame(width: 380, height: 240, alignment: .top)
            .allowsHitTesting(false)
    }
}

private enum IslandPreviewGeometry {
    /// Expanded island uses the same continuous corner for its fill and clipping.
    static let expandedRadius: CGFloat = 44
}

/// Deterministic fixture updates; these never enter the actual ActivityKit stream.
private struct IslandPreviewSample {
    var state: PitPulseActivityAttributes.ContentState
    var numbers: ActivityPreviewNumbers
    init(state source: PitPulseActivityAttributes.ContentState, elapsed: Double, reduceMotion: Bool) {
        state = source
        let step = Int(elapsed / 5) % 4
        let prior = (step + 3) % 4
        var previous: [String: String] = [:]
        func value(_ values: [String]) -> String {
            previous[values[step]] = values[prior]
            return values[step]
        }
        state.lapLabel = value(["L32/71", "L33/71", "L34/71", "L35/71"])
        let gap = value(["+0.842", "+0.716", "+0.584", "+0.691"])
        state.battleGap = gap; state.challengerGap = gap
        if var driver = state.trackedDriver {
            driver.gap = gap; driver.interval = gap
            let speed = [312, 318, 305, 321]
            previous["\(speed[step]) km/h"] = "\(speed[prior]) km/h"
            driver.speed = speed[step]
            driver.lastLap = value(["1:11.482", "1:11.368", "1:11.206", "1:11.417"])
            driver.tire = value(["M 18", "M 19", "M 20", "M 21"])
            if !driver.sectors.isEmpty {
                driver.sectors[0].time = value(["18.426", "18.372", "18.298", "18.411"])
            }
            state.trackedDriver = driver
        }
        if state.podium?.count ?? 0 > 1 { state.podium?[1].gap = gap }
        if state.battleDrivers?.count ?? 0 > 1 {
            state.battleDrivers?[1].gap = gap
            state.battleDrivers?[1].tire = state.trackedDriver?.tire
        }
        let phase = elapsed.truncatingRemainder(dividingBy: 5) / 0.32
        numbers = .init(previous: elapsed < 5 ? [:] : previous, progress: min(1, 1 - pow(1 - min(1, phase), 3)), reduceMotion: reduceMotion)
    }
}

private struct PositionChangesPreview: View {
    typealias Driver = PitPulseActivityAttributes.Driver
    let elapsed: Double
    let reduceMotion: Bool
    private let rowHeight: CGFloat = 27
    private var cars: [Driver] {
        [("Lando NORRIS", "norris"), ("Max VERSTAPPEN", "max_verstappen"),
         ("Charles LECLERC", "leclerc"), ("Oscar PIASTRI", "piastri"),
         ("George RUSSELL", "russell"), ("Lewis HAMILTON", "hamilton"),
         ("Fernando ALONSO", "alonso"), ("Carlos SAINZ", "sainz"),
         ("Pierre GASLY", "gasly"), ("Alex ALBON", "albon"),
         ("Esteban OCON", "ocon"), ("Lance STROLL", "stroll"),
         ("Kimi ANTONELLI", "antonelli"), ("Oliver BEARMAN", "bearman"),
         ("Liam LAWSON", "lawson"), ("Isack HADJAR", "hadjar"),
         ("Nico HULKENBERG", "hulkenberg"), ("Gabriel BORTOLETO", "bortoleto"),
         ("Franco COLAPINTO", "colapinto"), ("Sergio PEREZ", "perez"),
         ("Valtteri BOTTAS", "bottas"), ("Arvid LINDBLAD", "arvid_lindblad")].map {
            Driver(name: $0.0, asset: "helmet-\($0.1)-2026")
        }
    }
    private static let eventTimes: [Double] = [0, 12, 15, 19, 24, 28, 40, 52, 64, 76]
    static func event(at elapsed: Double) -> Int {
        let time = elapsed.truncatingRemainder(dividingBy: 100)
        return eventTimes.lastIndex(where: { $0 <= time }) ?? 0
    }
    static func phase(at elapsed: Double) -> Double {
        elapsed.truncatingRemainder(dividingBy: 100) - eventTimes[event(at: elapsed)]
    }
    private func order(_ scene: Int) -> [Int] {
        var result = Array(0..<22)
        guard scene > 0, scene < 9 else { return result }
        for index in 1...scene {
            switch index {
            case 1: result.swapAt(6, 7)
            case 2: result.swapAt(7, 8)
            case 3: result.swapAt(8, 9)
            case 4: result.swapAt(9, 10)
            case 5: result.swapAt(10, 11)
            case 6: result.swapAt(2, 3)
            case 7: result.swapAt(4, 5); result.swapAt(16, 17)
            case 8: result.swapAt(0, 1)
            default: break
            }
        }
        return result
    }
    private func positions(_ order: [Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: order.enumerated().map { (String($0.element), $0.offset + 1) })
    }
    private func focus(_ scene: Int) -> Int {
        var tracker = IslandPositionFocus()
        tracker.update(positions: positions(order(0)), now: 0)
        if scene > 0 {
            for index in 1...scene { tracker.update(positions: positions(order(index)), now: Self.eventTimes[index]) }
        }
        return tracker.driverID.flatMap(Int.init) ?? 0
    }
    private func eased(_ t: Double) -> Double { let x = min(1, max(0, t)); return 1 - pow(1 - x, 3) }
    var body: some View {
        let scene = Self.event(at: elapsed)
        let phase = Self.phase(at: elapsed)
        let old = order(scene == 0 ? 9 : scene - 1), next = order(scene)
        let oldFocus = focus(scene == 0 ? 9 : scene - 1), nextFocus = focus(scene)
        let exchange = reduceMotion ? 1 : eased((phase - 0.65) / 0.65)
        // While the same car keeps changing position, move its viewport along
        // with the rows so the focused helmet stays anchored in the center.
        let scroll = oldFocus == nextFocus ? exchange : (reduceMotion ? 1 : eased(phase / 0.65))
        let oldStart = min(17, max(0, (old.firstIndex(of: oldFocus) ?? 0) - 2))
        let newStart = min(17, max(0, (next.firstIndex(of: nextFocus) ?? 0) - 2))
        let start = Double(oldStart) + Double(newStart - oldStart) * scroll
        let leaderID = (exchange < 0.5 ? old : next)[0]
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("LAP").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    ActivityNumberText("\(32 + min(scene, 5))/71").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("LIVE").font(.system(size: 7, weight: .heavy)).padding(.horizontal, 4).padding(.vertical, 2).background(.white, in: Capsule()).foregroundStyle(.black)
                }
                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                HStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("P1").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(MotorsportAssetName.abbreviation(cars[leaderID].name))
                            .font(.system(size: 17, weight: .heavy)).foregroundStyle(PulseStyle.red)
                    }
                    if let asset = cars[leaderID].asset { MotorsportImages.image(named: asset).resizable().scaledToFit().frame(width: 44, height: 44) }
                }
            }.frame(width: 105, alignment: .leading)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(0..<22, id: \.self) { id in
                        let a = old.firstIndex(of: id)!, b = next.firstIndex(of: id)!
                        let position = exchange < 0.5 ? a + 1 : b + 1
                        HStack(spacing: 5) {
                            ActivityNumberText("\(b + 1)")
                                .environment(\.activityPreviewNumbers, .init(previous: ["\(b + 1)": "\(a + 1)"], progress: exchange, reduceMotion: reduceMotion))
                                        .font(.system(size: 10, weight: .semibold)).frame(width: 16)
                            if let asset = cars[id].asset { MotorsportImages.image(named: asset).resizable().scaledToFit().frame(width: 25, height: 25) }
                            Text(MotorsportAssetName.abbreviation(cars[id].name)).font(.system(size: 10, weight: .semibold))
                            if a != b {
                                Image(systemName: b < a ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                    .font(.system(size: 7)).foregroundStyle(b < a ? .green : .red)
                            }
                            Spacer(minLength: 0)
                            Text(position == 1 ? "LEADER" : String(format: "+%.3f", Double(position - 1) * 1.271 + Double(id) * 0.023))
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4).frame(width: geometry.size.width, height: rowHeight)
                        .background(id == nextFocus ? Color.red.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .opacity(a != b && id != nextFocus ? 1 - 0.65 * sin(.pi * exchange) : 1)
                        .zIndex(id == nextFocus ? 1 : 0)
                        .offset(x: a == b ? 0 : (id == nextFocus ? 9 : -9) * sin(.pi * exchange),
                                y: (Double(a) + Double(b - a) * exchange - start) * rowHeight)
                    }
                }
            }.frame(height: rowHeight * 5).clipped()
        }.frame(height: rowHeight * 5)
        .accessibilityElement(children: .combine)
    }
}
