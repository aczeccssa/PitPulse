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
        if name.hasPrefix("helmet-") || name.hasPrefix("driver-photo-") { return "person.crop.circle" }
        return nil
    }

    #if os(macOS)
    public static func nsImage(named name: String) -> NSImage? {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return artworkURL(named: name, dark: dark).flatMap { NSImage(contentsOf: $0) }
    }
    #elseif os(iOS)
    public static func uiImage(named name: String, traits: UITraitCollection? = nil) -> UIImage? {
        let dark = (traits ?? UITraitCollection.current).userInterfaceStyle == .dark
        return artworkURL(named: name, dark: dark).flatMap { UIImage(contentsOfFile: $0.path) }
    }
    #endif

    private static func artworkURL(named name: String, dark: Bool) -> URL? {
        if name.hasPrefix("flag-") {
            return cachedImage(stems: [name], group: "native-flags")
                ?? cachedImage(stems: [name], group: "flags")
        }
        if name.hasPrefix("web-nav-") || name.hasPrefix("web-result-") {
            return cachedImage(stems: [name], group: "native-navigation")
        }
        let kinds: [(String, MotorsportAssetName.Kind)] = [
            ("driver-photo", .driverPhoto), ("team-logo", .teamLogo), ("car-side", .carSide), ("helmet", .helmet)
        ]
        guard let (prefix, kind) = kinds.first(where: { name.hasPrefix($0.0 + "-") }),
              let split = name.lastIndex(of: "-"),
              name.distance(from: name.startIndex, to: split) > prefix.count + 1,
              let season = Int(name[name.index(after: split)...]) else {
            return cachedImage(stems: [name], group: "native-brand")
        }
        let nativeNames = kind == .teamLogo && dark ? [name + "-dark", name] : [name]
        if let url = cachedImage(stems: nativeNames, group: "native-\(season)/\(prefix)") { return url }
        let id = String(name[name.index(name.startIndex, offsetBy: prefix.count + 1)..<split])
        let slug = LiveIslandLogic.assetSlug(id).replacingOccurrences(of: "-", with: "_")
        let candidates = [MotorsportAssetName.canonicalID(kind: kind, id: slug), id, slug]
        let stems = kind == .teamLogo && dark ? candidates.map { $0 + "-dark" } + candidates : candidates
        return cachedImage(stems: stems, group: "\(season)/\(prefix)")
    }

    private static func cachedImage(stems: [String], group: String) -> URL? {
        for stem in stems {
            if let file = MediaCache.shared.file(group: group, name: stem + ".png") { return file }
        }
        return nil
    }
}
