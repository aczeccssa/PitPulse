import AppKit
import SwiftUI
import SharedData

struct LiveTeamLogo: View {
    let driver: LiveDriver
    let season: Int
    var isWec = false
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let id = LiveIslandLogic.teamAssetID(for: driver, isWec: isWec),
               let image = MotorsportAsset.image(kind: .teamLogo, id: id, season: season) {
                Image(nsImage: image).resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

