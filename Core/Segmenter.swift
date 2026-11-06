import Foundation
import CoreGraphics
import Vision

/// Coarse subject probability from Apple's foreground model.
///
/// Apple's model predicts on a 512 x 512 grid whatever the photo size, so a single pass
/// gives a soft, low-detail outline. When the item fills only part of the frame we run a
/// second pass on a crop around it, which spends the model's whole grid on the item and
/// roughly doubles to quadruples the detail along its edges.
public struct Segmentation {
    /// Probability 0...1 at the working resolution.
    public var prob: Plane
    public var instanceCount: Int
    public var zoomed: Bool
}

public enum Segmenter {
    public static let workLongSide = 1536

    public static func segment(_ full: CGImage, zoom: Bool = true) throws -> Segmentation? {
        let fw = full.width, fh = full.height
        let k = Float(workLongSide) / Float(max(fw, fh))
        let ww = max(1, Int((Float(fw) * min(1, k)).rounded())), wh = max(1, Int((Float(fh) * min(1, k)).rounded()))
        guard let work = scaled(full, width: ww, height: wh) else { return nil }
        // No subject found: an empty map, so the surface can still be used (close-ups).
        guard let first = try mask(of: work) else {
            return Segmentation(prob: Plane(width: ww, height: wh, value: 0), instanceCount: 0, zoomed: false)
        }
        var prob = first.prob
        var zoomed = false

        // Bounding box of the item at working resolution.
        if let box = bbox(prob, threshold: 0.5) {
            let area = Float(box.width * box.height) / Float(ww * wh)
            if zoom && area < 0.55 {
                // Crop around the item with a margin, from the full-resolution photo.
                let margin = 0.12 * Float(max(box.width, box.height))
                let x0 = max(0, Float(box.minX) - margin), y0 = max(0, Float(box.minY) - margin)
                let x1 = min(Float(ww), Float(box.maxX) + margin), y1 = min(Float(wh), Float(box.maxY) + margin)
                let s = Float(fw) / Float(ww)
                let crop = CGRect(x: CGFloat(x0 * s), y: CGFloat(y0 * s), width: CGFloat((x1 - x0) * s), height: CGFloat((y1 - y0) * s)).integral
                if let cropped = full.cropping(to: crop) {
                    let ck = Float(workLongSide) / Float(max(cropped.width, cropped.height))
                    let cw = max(1, Int((Float(cropped.width) * min(1, ck)).rounded()))
                    let ch = max(1, Int((Float(cropped.height) * min(1, ck)).rounded()))
                    if let cimg = scaled(cropped, width: cw, height: ch), let second = try mask(of: cimg) {
                        // Paste the crop's probability back into the working frame.
                        let rx = Int((Float(crop.minX) / s).rounded()), ry = Int((Float(crop.minY) / s).rounded())
                        let rw = max(1, Int((Float(crop.width) / s).rounded())), rh = max(1, Int((Float(crop.height) / s).rounded()))
                        let patch = second.prob.resized(width: rw, height: rh)
                        // Outside the crop the first pass stands; inside, the detailed pass replaces it,
                        // blended over a few pixels at the crop border.
                        let feather = 6
                        for y in 0..<rh {
                            let ty = ry + y
                            if ty < 0 || ty >= wh { continue }
                            for x in 0..<rw {
                                let tx = rx + x
                                if tx < 0 || tx >= ww { continue }
                                let edge = min(min(x, rw - 1 - x), min(y, rh - 1 - y))
                                let w = min(1, Float(edge) / Float(feather))
                                let i = ty * ww + tx
                                prob.data[i] = prob.data[i] * (1 - w) + patch.data[y * rw + x] * w
                            }
                        }
                        zoomed = true
                    }
                }
            }
        }
        return Segmentation(prob: prob, instanceCount: first.instances, zoomed: zoomed)
    }

    private static func mask(of image: CGImage) throws -> (prob: Plane, instances: Int)? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        guard let obs = request.results?.first, !obs.allInstances.isEmpty else { return nil }
        let buffer = try obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let rowFloats = CVPixelBufferGetBytesPerRow(buffer) / 4
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: Float.self) else { return nil }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w { out[y * w + x] = max(0, min(1, base[y * rowFloats + x])) }
        }
        var p = Plane(width: w, height: h, data: out)
        if w != image.width || h != image.height { p = p.resized(width: image.width, height: image.height) }
        return (p, obs.allInstances.count)
    }

    static func scaled(_ cg: CGImage, width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: ColourSpaces.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// Bounding box (top-left origin, pixels) of values above threshold.
    public static func bbox(_ p: Plane, threshold: Float) -> (minX: Int, minY: Int, maxX: Int, maxY: Int, width: Int, height: Int)? {
        var minX = p.width, minY = p.height, maxX = -1, maxY = -1
        for y in 0..<p.height {
            let row = y * p.width
            for x in 0..<p.width where p.data[row + x] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX + 1, maxY + 1, maxX + 1 - minX, maxY + 1 - minY)
    }
}
