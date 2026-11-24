import SharedData
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Shared catalog and season archive access for apps and extensions.
public enum MotorsportImages {
    @MainActor
    public static func image(named name: String) -> Image {
        #if os(macOS)
        if let image = nsImage(named: name) { return Image(nsImage: image) }
        #elseif os(iOS)
        if let image = uiImage(named: name) { return Image(uiImage: image) }
        #endif
        if let symbol = fallbackSymbol(named: name) { return Image(systemName: symbol) }
        return Image(name, bundle: .module)
    }

    public static func fallbackSymbol(named name: String) -> String? {
        if name.hasPrefix("team-logo-") { return "shield" }
        if name.hasPrefix("car-side-") { return "car.side" }
        if name.hasPrefix("helmet-") || name.hasPrefix("driver-photo-") { return "person.crop.circle" }
        return nil
    }

    #if os(macOS)
    public static func nsImage(named name: String) -> NSImage? {
        Bundle.module.image(forResource: NSImage.Name(name))
            ?? artworkURL(named: name, dark: false).flatMap { NSImage(contentsOf: $0) }
    }
    #elseif os(iOS)
    @MainActor
    public static func uiImage(named name: String, traits: UITraitCollection? = nil) -> UIImage? {
        UIImage(named: name, in: .module, compatibleWith: traits)
            ?? artworkURL(named: name, dark: traits?.userInterfaceStyle == .dark).flatMap {
                UIImage(contentsOfFile: $0.path)
            }
    }
    #endif

    private static func artworkURL(named name: String, dark: Bool) -> URL? {
        if name.hasPrefix("flag-") {
            return rawImageURL(stems: [name], in: "WebAssets/motorsport")
        }
        let kinds: [(String, MotorsportAssetName.Kind)] = [
            ("driver-photo", .driverPhoto), ("team-logo", .teamLogo), ("car-side", .carSide), ("helmet", .helmet)
        ]
        guard let (prefix, kind) = kinds.first(where: { name.hasPrefix($0.0 + "-") }),
              let split = name.lastIndex(of: "-"),
              name.distance(from: name.startIndex, to: split) > prefix.count + 1,
              let season = Int(name[name.index(after: split)...]) else { return nil }
        let id = String(name[name.index(name.startIndex, offsetBy: prefix.count + 1)..<split])
        let slug = LiveIslandLogic.assetSlug(id).replacingOccurrences(of: "-", with: "_")
        let candidates = [MotorsportAssetName.canonicalID(kind: kind, id: slug), id, slug]
        let stems = kind == .teamLogo && dark ? candidates.map { $0 + "-dark" } + candidates : candidates
        return rawImageURL(stems: stems, in: "motorsport/\(season)/\(prefix)")
    }

    private static func rawImageURL(stems: [String], in subdirectory: String) -> URL? {
        // Extensions use the archive embedded in their enclosing application.
        var url = Bundle.main.bundleURL
        while url.pathExtension != "app" {
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path, !parent.path.isEmpty else { return nil }
            url = parent
        }
        guard let bundle = Bundle(url: url) else { return nil }
        for stem in stems where !stem.isEmpty && !stem.contains("/") && stem != "." && stem != ".." {
            if let file = bundle.url(forResource: stem, withExtension: "png", subdirectory: subdirectory) {
                return file
            }
        }
        return nil
    }
}
