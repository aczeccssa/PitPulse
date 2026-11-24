import AppKit
import SwiftUI
import SharedData
import SharedComponents

struct LiveHelmetView: View {
    @ObservedObject var model: AppModel
    let driver: LiveDriver
    let size: CGFloat
    let snapshot: LiveSnapshot

    private var image: NSImage? {
        let season = snapshot.artworkSeason(replaySeason: model.selectedSeason)
        if snapshot.isWec {
            guard let id = LiveIslandLogic.driverAssetID(for: driver) else { return nil }
            return MotorsportAsset.image(kind: .driverPhoto, id: id, season: season)
        }
        let id = LiveIslandLogic.rosterID(for: driver, favorites: model.favoriteDrivers)
        return MotorsportImages.nsImage(named: MotorsportAssetName.helmetName(
            driverID: id, name: driver.name ?? "", season: season
        ))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text(MotorsportAsset.abbreviation(driver.name ?? driver.number))
                    .font(.system(size: size / 3, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

