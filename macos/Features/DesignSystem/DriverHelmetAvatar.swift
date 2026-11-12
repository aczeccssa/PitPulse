import AppKit
import SwiftUI
import SharedData

/// Drivers are always represented by a helmet. A portrait is never used as a
/// stand-in; drivers without a helmet asset get a neutral helmet glyph.
struct DriverHelmetAvatar: View {
    let driverID: String
    let name: String
    let season: Int
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let image = MotorsportAsset.f1HelmetImage(id: driverID, season: season) {
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
