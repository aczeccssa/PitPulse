import SharedComponents
import ActivityKit
import SwiftUI
import WidgetKit
import SharedData

struct PitPulseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PitPulseActivityAttributes.self) { context in
            VStack(spacing: 6) {
                if showsHeader(context.state) {
                    HStack {
                        ActivityHeader(state: context.state)
                        Spacer()
                        ActivityStatus(state: context.state, expired: context.isStale)
                    }.padding(.horizontal, 12)
                }
                ActivityPayloadView(state: displayState(context.state, expired: context.isStale))

            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "pitpulse://live"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if showsHeader(context.state) {
                        ActivityHeader(state: context.state).padding(.leading, 20).padding(.top, 8)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if showsHeader(context.state) {
                        ActivityStatus(state: context.state, expired: context.isStale)
                            .padding(.trailing, 18).padding(.top, 8)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ActivityPayloadView(state: displayState(context.state, expired: context.isStale))
                    }.padding(.horizontal, 12).padding(.bottom, 8)
                        .environment(\.colorScheme, .dark)
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
    private func showsHeader(_ state: PitPulseActivityAttributes.ContentState) -> Bool {
        state.presentation != IslandContentMode.favorite.rawValue && state.presentation != IslandContentMode.positionChanges.rawValue
    }
    private func displayState(_ state: PitPulseActivityAttributes.ContentState, expired: Bool) -> PitPulseActivityAttributes.ContentState {
        var result = state
        result.isStale = state.isStale || expired
        return result
    }
    private func compactValue(_ state: PitPulseActivityAttributes.ContentState) -> String {
        state.compactTrailingText
    }
}
