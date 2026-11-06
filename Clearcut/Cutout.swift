import Foundation
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Background removal using Apple's own subject-lifting model (the same one Photos uses).
enum Cutout {
    /// Returns the subject (all detected foreground instances) on a transparent background,
    /// cropped to the subject, at the input image's resolution. Nil when no subject is found.
    static func subject(from cg: CGImage) throws -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )
        return CIImage(cvPixelBuffer: buffer)
    }
}

enum ImageFiles {
    /// Decodes image data with its orientation applied, limited to maxPixel on the longest side.
    static func loadOriented(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    static func loadOriented(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return loadOriented(data, maxPixel: maxPixel)
    }

    static func scaled(_ cg: CGImage, maxSide: CGFloat) -> CGImage? {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let k = min(1, maxSide / max(w, h))
        let nw = max(1, Int((w * k).rounded())), nh = max(1, Int((h * k).rounded()))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Renderer.sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }

    static func encode(_ cg: CGImage, type: UTType, quality: CGFloat = 0.92) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
