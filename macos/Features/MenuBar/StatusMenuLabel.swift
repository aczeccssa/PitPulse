import AppKit
import SwiftUI
import PitPulseData

struct StatusMenuLabel: View {
    let symbol: AppSymbol

    /// The menu bar needs a monochrome template mark; the popup header keeps
    /// the brand colour. The status item uses the NSImage size, because
    /// `MenuBarExtra` ignores SwiftUI frame modifiers.
    private var mark: NSImage? {
        guard let image = NSImage(named: "PitPulseMenuBar")?.copy() as? NSImage else { return nil }
        let height: CGFloat = 16
        image.size = NSSize(width: height * image.size.width / image.size.height, height: height)
        image.isTemplate = true
        return image
    }

    var body: some View {
        Group {
            if let mark {
                Image(nsImage: mark)
            } else {
                Image(systemName: symbol.resolvedSystemName())
            }
        }
        .accessibilityLabel(symbol.accessibilityLabel)
        .help(symbol.accessibilityLabel)
    }
}
