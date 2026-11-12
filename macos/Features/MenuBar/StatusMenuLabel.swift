import SwiftUI
import PitPulseData

struct StatusMenuLabel: View {
    let symbol: AppSymbol

    var body: some View {
        // Compact brand mark cropped to the 20 × 18 pt menu bar canvas.
        Image("MenuBarIcon")
            .renderingMode(.template)
            .accessibilityLabel(symbol.accessibilityLabel)
            .help(symbol.accessibilityLabel)
    }
}
