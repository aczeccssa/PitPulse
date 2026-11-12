import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Shared catalog access for the apps, extensions and Canvas previews.
public enum MotorsportImages {
    public static func image(named name: String) -> Image {
        Image(name, bundle: .module)
    }

    #if os(macOS)
    public static func nsImage(named name: String) -> NSImage? {
        Bundle.module.image(forResource: NSImage.Name(name))
    }
    #elseif os(iOS)
    @MainActor
    public static func uiImage(named name: String, traits: UITraitCollection? = nil) -> UIImage? {
        UIImage(named: name, in: .module, compatibleWith: traits)
    }
    #endif
}
