import Foundation
import CoreGraphics
import Vision

/// Subject probability at working resolution, from the cutout network (BiRefNet) when it is
/// available, otherwise from Apple's foreground model.
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

    public static func segment(_ full: CGImage, zoom: Bool = true, network: CutoutNetwork? = nil) throws -> Segmentation? {
        let fw = full.width, fh = full.height
        let k = Float(workLongSide) / Float(max(fw, fh))
        let ww = max(1, Int((Float(fw) * min(1, k)).rounded())), wh = max(1, Int((Float(fh) * min(1, k)).rounded()))
        if let network { return try networkSegment(full, ww: ww, wh: wh, zoom: zoom, network: network) }
        guard let work = scaled(full, width: ww, height: wh) else { return nil }
        // No subject found: an empty map, so the surface can still be used (close-ups).
        guard let first = try mask(of: work, network: network) else {
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
                    if let cimg = scaled(cropped, width: cw, height: ch), let second = try mask(of: cimg, network: network) {
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

    // MARK: Cutout network

    /// Two passes of the cutout network.
    ///
    /// 1. Context: the whole photo on a larger neutral grey canvas. A cutout network picks out
    ///    "the object"; on a close-up where the garment runs off the frame it would otherwise pick
    ///    the most distinct thing inside it (a tape measure, a label). With room around it, the
    ///    garment itself is the object.
    /// 2. Detail: a tighter crop around the item, grey added only on sides where the item runs off
    ///    the frame, so the network spends its 1024 pixels on the item. Used where it agrees
    ///    with the context pass; if it doesn't (it picked out a part), the context pass stands.
    static func networkSegment(_ full: CGImage, ww: Int, wh: Int, zoom: Bool, network: CutoutNetwork) throws -> Segmentation? {
        let fw = CGFloat(full.width), fh = CGFloat(full.height)
        let m = 0.35 * max(fw, fh)
        let whole = CGRect(x: 0, y: 0, width: fw, height: fh)
        guard var prob = try pass(full, region: whole, pads: (m, m, m, m), outW: ww, outH: wh, network: network) else { return nil }
        guard prob.data.contains(where: { $0 > 0.5 }) else { return nil }
        var zoomed = false
        if zoom, let box = bbox(prob, threshold: 0.5) {
            let s = fw / CGFloat(ww)
            let margin = 0.08 * CGFloat(max(box.width, box.height)) * s
            var r = CGRect(x: CGFloat(box.minX) * s - margin, y: CGFloat(box.minY) * s - margin,
                           width: CGFloat(box.width) * s + 2 * margin, height: CGFloat(box.height) * s + 2 * margin).intersection(whole).integral
            r = r.intersection(whole)
            // Only worth it when the crop is clearly smaller than the photo.
            if r.width * r.height < 0.8 * fw * fh {
                let pad = 0.12 * max(r.width, r.height)
                let touch = (l: r.minX <= 1, t: r.minY <= 1, r: r.maxX >= fw - 1, b: r.maxY >= fh - 1)
                let pads = (touch.l ? pad : 0, touch.t ? pad : 0, touch.r ? pad : 0, touch.b ? pad : 0)
                let rx = Int((r.minX / s).rounded()), ry = Int((r.minY / s).rounded())
                let rw = max(1, min(ww - rx, Int((r.width / s).rounded()))), rh = max(1, min(wh - ry, Int((r.height / s).rounded())))
                if let detail = try pass(full, region: r, pads: pads, outW: rw, outH: rh, network: network) {
                    // Agreement inside the crop.
                    var inter = 0, uni = 0
                    for y in 0..<rh { for x in 0..<rw {
                        let a = prob.data[(ry + y) * ww + rx + x] > 0.5, b = detail.data[y * rw + x] > 0.5
                        if a && b { inter += 1 }
                        if a || b { uni += 1 }
                    } }
                    if uni > 0 && Float(inter) / Float(uni) > 0.9 {
                        let feather = 6
                        for y in 0..<rh { for x in 0..<rw {
                            let edge = min(min(x, rw - 1 - x), min(y, rh - 1 - y))
                            // Where the crop meets the frame there is no seam to blend.
                            let atFrame = (x == 0 && rx == 0) || (y == 0 && ry == 0) || (x == rw - 1 && rx + rw >= ww) || (y == rh - 1 && ry + rh >= wh)
                            let w = atFrame ? 1 : min(1, Float(edge) / Float(feather))
                            let i = (ry + y) * ww + rx + x
                            prob.data[i] = prob.data[i] * (1 - w) + detail.data[y * rw + x] * w
                        } }
                        zoomed = true
                    }
                }
            }
        }
        return Segmentation(prob: prob, instanceCount: 1, zoomed: zoomed)
    }

    /// Runs the network on a region of the photo set on a neutral grey canvas with the given
    /// padding (left, top, right, bottom, in photo pixels). Returns the region's probability
    /// at outW x outH.
    private static func pass(_ full: CGImage, region: CGRect, pads: (CGFloat, CGFloat, CGFloat, CGFloat),
                             outW: Int, outH: Int, network: CutoutNetwork) throws -> Plane? {
        let side = CutoutNetwork.side
        let cw = region.width + pads.0 + pads.2, ch = region.height + pads.1 + pads.3
        let sx = CGFloat(side) / cw, sy = CGFloat(side) / ch
        guard let crop = region == CGRect(x: 0, y: 0, width: full.width, height: full.height) ? full : full.cropping(to: region),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: ColourSpaces.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.interpolationQuality = .high
        // Core Graphics draws from the bottom left, so the bottom pad comes first.
        ctx.draw(crop, in: CGRect(x: pads.0 * sx, y: pads.3 * sy, width: region.width * sx, height: region.height * sy))
        guard let canvas = ctx.makeImage(), let p = try network.probability(of: canvas) else { return nil }
        // The region inside the canvas, in the probability map's top-left coordinates.
        let x0 = Float(pads.0 * sx), y0 = Float(pads.1 * sy), w = Float(region.width * sx), h = Float(region.height * sy)
        var out = [Float](repeating: 0, count: outW * outH)
        for y in 0..<outH {
            let fy = y0 + (Float(y) + 0.5) / Float(outH) * h - 0.5
            for x in 0..<outW {
                let fx = x0 + (Float(x) + 0.5) / Float(outW) * w - 0.5
                out[y * outW + x] = p.sample(fx, fy)
            }
        }
        return Plane(width: outW, height: outH, data: out)
    }

    private static func mask(of image: CGImage, network: CutoutNetwork?) throws -> (prob: Plane, instances: Int)? {
        if let network {
            guard let p = try network.probability(of: image) else { return nil }
            guard p.data.contains(where: { $0 > 0.5 }) else { return nil }
            return (p, 1)
        }
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
