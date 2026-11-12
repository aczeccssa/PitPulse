import PitPulseComponents
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
                        ActivityNumberText(context.state.lapLabel).font(.title3.bold().monospacedDigit())
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
                        if context.state.presentation != IslandContentMode.overview.rawValue && context.state.presentation != IslandContentMode.positionChanges.rawValue {
                            ActivityNumberText(context.state.lapLabel).font(.caption.bold().monospacedDigit())
                        }
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
                        if context.state.presentation != IslandContentMode.overview.rawValue && context.state.presentation != IslandContentMode.positionChanges.rawValue {
                        HStack {
                            Image(systemName: "flag.fill").foregroundStyle(context.state.trackColor)
                            Text(context.state.trackLabel ?? "等待赛道状态").lineLimit(1)
                            Spacer()
                            Text(context.state.isStale || context.isStale ? "数据过期" : (context.state.updatedLabel ?? ""))
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 12).environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    MotorsportImages.image(named: MotorsportAssetName.seriesLogoName(isWec: context.attributes.seriesTitle == "FIA WEC")).resizable().scaledToFit().frame(width: 24, height: 14)
                    ActivityNumberText(context.state.compactLeadingText).font(.system(size: 9, weight: .bold)).lineLimit(1)
                }.foregroundStyle(.red)
            } compactTrailing: {
                ActivityNumberText(context.isStale || context.state.isStale ? "过期" : compactValue(context.state))
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
        state.compactTrailingText
    }
}
