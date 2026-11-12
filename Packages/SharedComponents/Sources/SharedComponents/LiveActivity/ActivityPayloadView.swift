#if os(iOS)
import SwiftUI
import SharedData

public struct ActivityPayloadView: View {
    let state: PitPulseActivityAttributes.ContentState
    public init(state: PitPulseActivityAttributes.ContentState) { self.state = state }
    public var body: some View {
        switch state.presentation.flatMap(IslandContentMode.init(rawValue:)) ?? .overview {
        case .positionChanges:
            PositionChangesActivityView(state: state)
        case .battle:
            if state.battleDrivers?.count == 1 { TrackedDriverView(driver: state.battleDrivers![0], weather: state.weather) }
            else { BattleView(state: state) }
        case .favorite:
            TrackedDriverView(driver: state.trackedDriver ?? .init(name: state.favoriteName ?? "请先收藏一位车手", position: state.favoritePosition, asset: state.favoriteAsset, gap: state.favoriteGap), weather: state.weather)
        case .overview:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    ActivityNumberText(state.lapLabel).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                    Spacer()
                    Label(state.trackLabel ?? "等待赛道状态", systemImage: "flag.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(state.trackColor).lineLimit(1)
                }
                if let progress = state.lapProgress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.14))
                            Capsule().fill(state.trackColor).frame(width: geometry.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("比赛进度")
                    .accessibilityValue("\(Int(progress * 100))%")
                }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array((state.podium ?? []).prefix(3).enumerated()), id: \.offset) { _, driver in
                        VStack(spacing: 3) {
                            DriverPortrait(driver: driver, size: 48)
                            ActivityNumberText(driver.position == 1 ? "LEADER" : driver.gap ?? "—").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }

            }
        }
    }
}

struct PositionChangesActivityView: View {
    let state: PitPulseActivityAttributes.ContentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var themeRed: Color { Color(red: 0.98, green: 0.25, blue: 0.23) }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LAP").font(.system(size: 9)).foregroundStyle(.secondary)
                ActivityNumberText(state.lapLabel).font(.system(size: 18, weight: .bold, design: .rounded))
                Divider()
                HStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("P1").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(state.leaderName.map(MotorsportAssetName.abbreviation) ?? "—")
                            .font(.system(size: 14, weight: .heavy)).foregroundStyle(themeRed)
                    }
                    if let asset = state.leaderAsset { ActivityHelmet(asset: asset, size: 30) }
                }
            }.frame(width: 98, alignment: .leading)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(state.positionDrivers ?? [], id: \.name) { driver in
                        HStack(spacing: 5) {
                            ActivityNumberText(driver.position.map(String.init) ?? "—").frame(width: 16)
                            if let asset = driver.asset { ActivityHelmet(asset: asset, size: 18) }
                            Text(MotorsportAssetName.abbreviation(driver.name)).fontWeight(.semibold)
                            if let delta = driver.positionChange, delta != 0 {
                                Image(systemName: delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                    .font(.system(size: 7)).foregroundStyle(delta > 0 ? .green : .red)
                            }
                            Spacer(minLength: 0)
                            ActivityNumberText(driver.position == 1 ? "LEADER" : driver.gap ?? "—").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 9)).monospacedDigit()
                        .padding(.horizontal, 4).frame(width: geometry.size.width, height: 18)
                        .background(driver.name == state.positionFocus ? themeRed.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .offset(y: CGFloat((driver.position ?? 1) - 1 - (state.positionWindowStart ?? 0)) * 18)
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.65), value: state.positionDrivers)
            }.frame(height: 90).clipped()
        }.frame(height: 90)
    }
}

#endif
