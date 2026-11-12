import SceneKit
import SharedComponents
import SharedData
import SwiftUI

struct IslandLiquidSilhouette: View {
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
