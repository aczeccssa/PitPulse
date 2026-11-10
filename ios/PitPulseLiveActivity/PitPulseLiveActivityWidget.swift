import ActivityKit
import SwiftUI
import WidgetKit
import PitPulseShared

struct PitPulseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PitPulseActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.seriesTitle.uppercased()).font(.caption2.bold()).tracking(2).foregroundStyle(.red)
                        Text(context.state.meetingName).font(.headline).lineLimit(1)
                        Text(context.state.sessionName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(context.state.lapLabel).font(.title3.bold().monospacedDigit())
                        ActivityStatus(state: context.state, expired: context.isStale)
                    }
                }
                Divider().overlay(Color.primary.opacity(0.1))
                ActivityPayloadView(state: context.state)
                Text(context.state.trackLabel ?? "等待赛道状态").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(16)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "pitpulse://live"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.sessionName.uppercased()).font(.caption2.bold()).foregroundStyle(.red)
                        Text(context.state.lapLabel).font(.caption.bold().monospacedDigit())
                    }.padding(.leading, 12).padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityStatus(state: context.state, expired: context.isStale).padding(.trailing, 10).padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.meetingName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        ActivityPayloadView(state: context.state)
                        HStack {
                            Image(systemName: "flag.fill").foregroundStyle(.red)
                            Text(context.state.trackLabel ?? "等待赛道状态").lineLimit(1)
                            Spacer()
                            Text(context.state.isStale || context.isStale ? "数据过期" : (context.state.updatedLabel ?? ""))
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 12).environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(MotorsportAssetName.seriesLogoName(isWec: context.attributes.seriesTitle == "FIA WEC")).resizable().scaledToFit().frame(width: 24, height: 14)
                    Text(context.state.presentation == IslandContentMode.favorite.rawValue ? (context.state.favoriteName.map(MotorsportAssetName.abbreviation) ?? "收藏") : context.state.sessionName).font(.system(size: 9, weight: .bold)).lineLimit(1)
                }.foregroundStyle(.red)
            } compactTrailing: {
                Text(context.isStale || context.state.isStale ? "过期" : compactValue(context.state))
                    .font(.caption2.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(context.isStale || context.state.isStale ? .orange : .white)
            } minimal: {
                Image(systemName: context.isStale || context.state.isStale ? "clock.badge.exclamationmark" : "flag.checkered")
                    .foregroundStyle(context.isStale || context.state.isStale ? .orange : .red)
            }
            .keylineTint(.red)
            .widgetURL(URL(string: "pitpulse://live"))
        }
    }
    private func compactValue(_ state: PitPulseActivityAttributes.ContentState) -> String {
        if state.presentation == IslandContentMode.favorite.rawValue { return state.favoritePosition.map { "P\($0)" } ?? "—" }
        if state.presentation == IslandContentMode.battle.rawValue { return state.challengerGap ?? state.lapLabel }
        return state.lapLabel
    }
}

private struct ActivityStatus: View {
    let state: PitPulseActivityAttributes.ContentState
    let expired: Bool
    var body: some View {
        Text(state.isStale || expired ? "数据过期" : state.statusLabel)
            .font(.system(size: 10, weight: .bold)).lineLimit(1)
            .foregroundStyle(state.isStale || expired ? .orange : .red)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct ActivityPayloadView: View {
    let state: PitPulseActivityAttributes.ContentState
    var body: some View {
        switch state.presentation.flatMap(IslandContentMode.init(rawValue:)) ?? .overview {
        case .battle: BattleView(state: state)
        case .favorite:
            HStack(spacing: 10) {
                if let asset = state.favoriteAsset { Image(asset).resizable().scaledToFit().frame(width: 42, height: 36).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 4) {
                    Label("喜欢的车手", systemImage: "star.fill").font(.system(size: 9)).foregroundStyle(.red)
                    Text(state.favoriteName ?? "请在 App 中选择车手").font(.caption.bold()).lineLimit(1)
                    if state.favoriteName != nil && state.favoritePosition == nil { Text("不在当前比赛中").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 4)
                Text(state.favoritePosition.map { "P\($0)" } ?? "—").font(.headline.monospacedDigit())
                Text(state.favoriteGap ?? "—").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        case .overview:
            HStack {
                Label(state.trackLabel ?? "等待赛道状态", systemImage: "flag.fill").font(.caption).lineLimit(1)
                Spacer()
                Text("\(state.driverCount) 位车手").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct BattleView: View {
    let state: PitPulseActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 8) {
            driver(state.leaderName, asset: state.leaderAsset, rank: "P1")
            Spacer(minLength: 4)
            Text(state.challengerGap ?? state.leaderGap ?? "—")
                .font(.caption.bold().monospacedDigit()).foregroundStyle(.red).lineLimit(1)
            Spacer(minLength: 4)
            if state.challengerName != nil { driver(state.challengerName, asset: state.challengerAsset, rank: "P2") }
        }
    }
    private func driver(_ name: String?, asset: String?, rank: String) -> some View {
        HStack(spacing: 5) {
            if let asset { Image(asset).resizable().scaledToFit().frame(width: 40, height: 30).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 3) {
                Text(name.map(MotorsportAssetName.abbreviation) ?? "—").font(.caption2.bold()).lineLimit(1)
                Text(rank).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
}
