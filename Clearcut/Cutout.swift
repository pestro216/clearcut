import Foundation
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Background removal using Apple's own subject-lifting model (the one Photos uses),
/// refined for clean, hard product edges at the photo's full resolution.
enum Cutout {
    /// A context that leaves values untouched, for working on masks.
    static let maskContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])

    /// Returns an 8-bit greyscale mask the same size as `full` (white = item), or nil if no item was found.
    static func mask(for full: CGImage) throws -> CGImage? {
        let W = CGFloat(full.width), H = CGFloat(full.height)
        let input = ImageFiles.scaled(full, maxSide: 2048) ?? full

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: input, orientation: .up, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
        let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)

        var m = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        let e = m.extent
        m = m.transformed(by: CGAffineTransform(scaleX: W / e.width, y: H / e.height))

        // Vision's mask is soft (it is made at a lower resolution). Steepen the transition
        // around the 50% line so the edge becomes a clean ~1.5px anti-aliased line at full size.
        let k = min(12, max(3, max(W, H) / 550))
        let threshold: CGFloat = 0.5
        let b = 0.5 - threshold * k
        let sharp = m
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: b, y: b, z: b, w: 1)
            ])
            .applyingFilter("CIColorClamp")

        return maskContext.createCGImage(sharp, from: CGRect(x: 0, y: 0, width: W, height: H),
                                         format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
    }

    /// Bounding box of white pixels in a greyscale mask, normalised with a top-left origin.
    static func boundingBox(of mask: CGImage) -> CGRect {
        let w = mask.width, h = mask.height
        var bytes = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where bytes[row + x] > 127 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        // CGContext rows run top to bottom in memory, so y here is already top-origin.
        return CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(minY) / CGFloat(h),
                      width: CGFloat(maxX - minX + 1) / CGFloat(w), height: CGFloat(maxY - minY + 1) / CGFloat(h))
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

    /// Pixel size of the image once its orientation is applied, without decoding it.
    static func orientedSize(_ data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
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

    static func scaledGray(_ cg: CGImage, to size: CGSize) -> CGImage? {
        let nw = max(1, Int(size.width.rounded())), nh = max(1, Int(size.height.rounded()))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
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
