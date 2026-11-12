import AppKit
import SwiftUI
import SharedData

struct LiveHelmetView: View {
    @ObservedObject var model: AppModel
    let driver: LiveDriver
    let size: CGFloat
    var isWec = false

    private var image: NSImage? {
        if isWec {
            guard let id = LiveIslandLogic.driverAssetID(for: driver) else { return nil }
            return MotorsportAsset.image(kind: .driverPhoto, id: id, season: model.selectedSeason)
        }
        guard let id = LiveIslandLogic.rosterID(for: driver, favorites: model.favoriteDrivers) else { return nil }
        return MotorsportAsset.f1DriverImage(id: id, season: model.selectedSeason)
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

