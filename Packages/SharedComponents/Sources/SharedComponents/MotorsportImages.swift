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
            ?? bundledWebImage(named: name, traits: traits)
    }

    @MainActor
    private static func bundledWebImage(named name: String, traits: UITraitCollection?) -> UIImage? {
        if name.hasPrefix("flag-") {
            return rawImage(stems: [name], in: "WebAssets/motorsport")
        }
        guard let kind = ["driver-photo", "team-logo", "car-side", "helmet"].first(where: { name.hasPrefix($0 + "-") }),
              let split = name.lastIndex(of: "-"),
              name.distance(from: name.startIndex, to: split) > kind.count + 1,
              let season = Int(name[name.index(after: split)...]) else { return nil }
        let id = String(name[name.index(name.startIndex, offsetBy: kind.count + 1)..<split])
        let slug = id.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "_")
        let isDriver = kind == "helmet" || kind == "driver-photo"
        let aliases = ["verstappen": "max_verstappen", "lindblad": "arvid_lindblad",
                       "magnussen": "kevin_magnussen", "camara": "rafael_camara", "hirakawa": "ryo_hirakawa",
                       "checo_perez": "perez", "kimi_antonelli": "antonelli", "andrea_kimi_antonelli": "antonelli"]
        let candidates = [isDriver ? aliases[slug] ?? slug : slug, id, slug.replacingOccurrences(of: "_", with: "-")]
        let stems = kind == "team-logo" && traits?.userInterfaceStyle == .dark
            ? candidates.map { $0 + "-dark" } + candidates : candidates
        return rawImage(stems: stems, in: "motorsport/\(season)/\(kind)")
    }

    @MainActor
    private static func rawImage(stems: [String], in subdirectory: String) -> UIImage? {
        // A widget runs from PlugIns/*.appex, while Xcode copies the raw archive into the enclosing app.
        let executingBundle = Bundle.main
        let assetBundle = executingBundle.bundleURL.pathExtension == "appex"
            ? Bundle(url: executingBundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
            : executingBundle
        for stem in stems where !stem.isEmpty && !stem.contains("/") && stem != "." && stem != ".." {
            if let url = assetBundle?.url(forResource: stem, withExtension: "png", subdirectory: subdirectory),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        return nil
    }
    #endif
}
