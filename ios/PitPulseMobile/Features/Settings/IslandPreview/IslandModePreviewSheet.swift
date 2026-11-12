import SceneKit
import SharedComponents
import SharedData
import SwiftUI

/// A draft stays local to this sheet. Only Save changes the persisted mode.
typealias IslandPreviewPage = IslandContentMode

struct IslandModePreviewSheet: View {
    @EnvironmentObject var model: MobileModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var selection: IslandPreviewPage?
    @State var displayedMode: IslandPreviewPage?
    @State var islandExpanded = true
    @State var previewExpanded = true
    @State var tuningModel = false
    @State var modelPose = IslandModelPose()

    var mode: IslandPreviewPage { selection ?? IslandPreviewPage(rawValue: model.islandMode.rawValue)! }
    var descriptions: String {
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

    var modelTuner: some View {
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

    func poseSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
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

    func changeMode(by step: Int) {
        let modes = IslandPreviewPage.allCases
        guard let index = modes.firstIndex(of: mode) else { return }
        selection = modes[min(max(index + step, 0), modes.count - 1)]
    }

    func transitionIsland(to target: IslandPreviewPage) async {
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

    func previewState(_ mode: IslandPreviewPage) -> PitPulseActivityAttributes.ContentState {
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
