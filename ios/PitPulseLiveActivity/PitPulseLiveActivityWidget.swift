import ActivityKit
import SwiftUI
import WidgetKit
import PitPulseShared

struct PitPulseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PitPulseActivityAttributes.self) { context in
            LockScreenLiveView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.lapLabel)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(context.state.meetingName)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                        Text(context.state.leaderName ?? context.state.sessionName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Label(context.state.trackLabel ?? "赛道", systemImage: "flag.fill")
                        Spacer()
                        Text(context.state.isStale ? "数据过期" : (context.state.updatedLabel ?? "\(context.state.driverCount) 位车手"))
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                }
            } compactLeading: {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(context.state.lapLabel)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(.white)
            }
            .keylineTint(.red)
        }
    }
}

private struct LockScreenLiveView: View {
    let attributes: PitPulseActivityAttributes
    let state: PitPulseActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.caption)
                    Text(attributes.seriesTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(state.meetingName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.sessionName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(state.lapLabel)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(state.statusLabel)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(14)
    }
}
