import AppKit
import SwiftUI
import SharedData
import SharedComponents

/// Season-specific driver artwork for standings and historical results.
struct DriverAvatar: View {
    let driverID: String
    let name: String
    let season: Int
    var size: CGFloat = 26
    var media: MediaReference? = nil

    var body: some View {
        Group {
            if let image = media.flatMap({ MotorsportImages.nsImage(media: $0) })
                ?? MotorsportAsset.driverAvatar(id: driverID, season: season) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "helmet.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.primary.opacity(0.06), in: Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
