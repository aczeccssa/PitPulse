import SharedComponents
import ActivityKit
import SwiftUI
import WidgetKit
import SharedData

struct PitPulseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PitPulseActivityAttributes.self) { context in
            VStack(spacing: 6) {
                if needsRefresh(context) || showsHeader(context.state) {
                    HStack {
                        ActivityHeader(state: context.state)
                        Spacer()
                        if !needsRefresh(context) { ActivityStatus(state: context.state, expired: false) }
                    }.padding(.horizontal, 12)
                }
                payload(context)

            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "pitpulse://live"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if needsRefresh(context) || showsHeader(context.state) {
                        ActivityHeader(state: context.state).padding(.leading, 20).padding(.top, 8)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !needsRefresh(context) && showsHeader(context.state) {
                        ActivityStatus(state: context.state, expired: false)
                            .padding(.trailing, 18).padding(.top, 8)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        payload(context)
                    }.padding(.horizontal, 12).padding(.bottom, 8)
                        .environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    MotorsportImages.image(named: MotorsportAssetName.seriesLogoName(isWec: context.attributes.seriesTitle == "FIA WEC")).resizable().scaledToFit().frame(width: 24, height: 14)
                    if !needsRefresh(context) {
                        ActivityNumberText(context.state.compactLeadingText).font(.system(size: 9, weight: .bold)).lineLimit(1)
                    }
                }.foregroundStyle(.red)
            } compactTrailing: {
                ActivityNumberText(needsRefresh(context) ? "Open Live" : context.state.compactTrailingText)
                    .font(.caption2.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(needsRefresh(context) ? Color.secondary : Color.white)
            } minimal: {
                Image(systemName: needsRefresh(context) ? "arrow.clockwise" : "flag.checkered")
                    .foregroundStyle(needsRefresh(context) ? Color.secondary : Color.red)
            }
            .keylineTint(.red)
            .widgetURL(URL(string: "pitpulse://live"))
        }
    }
    private func showsHeader(_ state: PitPulseActivityAttributes.ContentState) -> Bool {
        state.presentation != IslandContentMode.favorite.rawValue && state.presentation != IslandContentMode.positionChanges.rawValue
    }
    private func needsRefresh(_ context: ActivityViewContext<PitPulseActivityAttributes>) -> Bool {
        context.isStale || context.state.isStale
    }

    @ViewBuilder private func payload(_ context: ActivityViewContext<PitPulseActivityAttributes>) -> some View {
        if needsRefresh(context) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.meetingName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Label("Open Live to refresh timing", systemImage: "arrow.clockwise")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ActivityPayloadView(state: context.state)
        }
    }
}
