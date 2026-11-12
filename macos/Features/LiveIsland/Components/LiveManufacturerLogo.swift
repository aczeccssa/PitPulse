import AppKit
import SwiftUI
import SharedData

struct LiveManufacturerLogo: View {
    let driver: LiveDriver
    let season: Int
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let id = LiveIslandLogic.wecManufacturerAssetID(for: driver),
               let image = MotorsportAsset.image(kind: .teamLogo, id: id, season: season) {
                // Keep the 32pt row slot but draw the mark at 80% so it does
                // not crowd the driver name.
                Image(nsImage: image).resizable().scaledToFit().padding(size * 0.1)
            } else {
                Text(MotorsportAsset.abbreviation(driver.manufacturer ?? driver.team ?? driver.number))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

