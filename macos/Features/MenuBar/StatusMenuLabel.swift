import SwiftUI
import SharedData
import SharedComponents

struct StatusMenuLabel: View {
    let symbol: AppSymbol

    var body: some View {
        // Compact brand mark cropped to the 20 × 18 pt menu bar canvas.
        MotorsportImages.image(named: "MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 18)
            .accessibilityLabel(symbol.accessibilityLabel)
            .help(symbol.accessibilityLabel)
    }
}
