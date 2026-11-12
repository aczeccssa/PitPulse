#if canImport(UIKit)
import UIKit

/// Pixel-backed RGBA textures for SceneKit; independent of device display scale.
@MainActor
public enum IslandPreviewTexture {
    // Fixed pixel dimensions and RGBA8 avoid UIKit's implicit @3x scaling
    // and grayscale formats unsupported by SceneKit's Metal texture loader.
    public static func make(width: Int, height: Int, draw: (CGContext) -> Void) -> UIImage {
        let bitmap = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        UIGraphicsPushContext(bitmap)
        draw(bitmap)
        UIGraphicsPopContext()
        return UIImage(cgImage: bitmap.makeImage()!, scale: 1, orientation: .up)
    }
}
#endif
