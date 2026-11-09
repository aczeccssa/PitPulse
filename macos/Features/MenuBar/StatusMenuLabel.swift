import SwiftUI
import PitPulseData

struct StatusMenuLabel: View {
    let symbol: AppSymbol

    var body: some View {
        Image(systemName: symbol.resolvedSystemName())
            .renderingMode(.template)
            .accessibilityLabel(symbol.accessibilityLabel)
            .help(symbol.accessibilityLabel)
    }
}
