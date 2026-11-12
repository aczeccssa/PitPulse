import SceneKit
import SharedComponents
import SharedData
import SwiftUI

struct PreviewDisplay: View {
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

    func iconRow(count: Int) -> some View {
        HStack(spacing: 22) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.white.opacity(0.12)).frame(width: 64, height: 64)
            }
        }
    }

}
