import SceneKit
import SharedComponents
import SharedData
import SwiftUI

struct IslandOverlay: View {
    let state: PitPulseActivityAttributes.ContentState
    let progress: Double
    let elapsed: Double
    let reduceMotion: Bool
    var sample: IslandPreviewSample { IslandPreviewSample(state: state, elapsed: elapsed, reduceMotion: reduceMotion) }

    // Keep every mode within the same preview height budget. The silhouette,
    // content frame and animated mask all derive their height from this value.
    let expandedHeight: CGFloat = 160

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
    var contentMask: some View {
        let width: CGFloat = 240 + 140 * progress
        let height: CGFloat = 36 + (expandedHeight - 36) * progress
        return RoundedRectangle(cornerRadius: IslandPreviewGeometry.expandedRadius, style: .continuous)
            .frame(width: width, height: height).frame(maxHeight: .infinity, alignment: .top)
    }
    var expandedContent: some View {
        VStack(spacing: 5) {
            if state.presentation != IslandContentMode.favorite.rawValue && state.presentation != IslandContentMode.positionChanges.rawValue {
                ActivityHeader(state: state).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
            Spacer(minLength: 0)
            if state.presentation == IslandPreviewPage.positionChanges.rawValue {
                PositionChangesPreview(elapsed: elapsed, reduceMotion: reduceMotion)
            } else {
                ActivityPayloadView(state: sample.state)
                    .environment(\.activityPreviewNumbers, sample.numbers)
            }
            Spacer(minLength: 0)

        }
    }

}
