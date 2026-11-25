import SharedData
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Shared artwork access for apps and extensions.
@MainActor
public enum MotorsportImages {
    public static func image(named name: String, fallback: String? = nil) -> Image {
        #if os(macOS)
        if let image = nsImage(named: name) { return Image(nsImage: image) }
        #elseif os(iOS)
        if let image = uiImage(named: name) { return Image(uiImage: image) }
        #endif
        return Image(systemName: fallback ?? fallbackSymbol(named: name) ?? "flag.checkered")
    }

    nonisolated public static func fallbackSymbol(named name: String) -> String? {
        if name.hasPrefix("team-logo-") { return "shield" }
        if name.hasPrefix("car-side-") { return "car.side" }
        if name.hasPrefix("helmet-") || name.hasPrefix("driver-photo-") || name.hasPrefix("avatar-") { return "person.crop.circle" }
        return nil
    }

    #if os(macOS)
    public static func nsImage(media: MediaReference) -> NSImage? {
        MediaCache.shared.file(group: media.group, name: media.file).flatMap { NSImage(contentsOf: $0) }
    }

    public static func nsImage(named name: String) -> NSImage? {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return artworkURL(named: name, dark: dark).flatMap { NSImage(contentsOf: $0) }
    }
    #elseif os(iOS)
    public static func uiImage(media: MediaReference) -> UIImage? {
        MediaCache.shared.file(group: media.group, name: media.file).flatMap { UIImage(contentsOfFile: $0.path) }
    }

    public static func uiImage(named name: String, traits: UITraitCollection? = nil) -> UIImage? {
        let dark = (traits ?? UITraitCollection.current).userInterfaceStyle == .dark
        return artworkURL(named: name, dark: dark).flatMap { UIImage(contentsOfFile: $0.path) }
    }
    #endif

    static func artworkURL(named name: String, dark: Bool, cache: MediaCache = .shared) -> URL? {
        if name.hasPrefix("avatar-helmet-") {
            return cache.file(named: name, kind: "driver-photo")
        }
        let kind = ["helmet", "driver-photo", "team-logo", "car-side"].first {
            name.hasPrefix($0 + "-")
        }
        return cache.file(named: name, variant: kind == "team-logo" && dark ? "dark" : nil, kind: kind)
    }
}
