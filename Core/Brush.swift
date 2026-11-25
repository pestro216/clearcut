import Foundation
import CoreGraphics

/// A manual touch-up stroke, stored in resolution-independent units so the same strokes can be
/// shown on a preview and applied to the full-resolution matte.
public struct BrushStroke: Codable, Hashable {
    /// Points as fractions of the photo's width and height (0...1, top-left origin).
    public var points: [CGPoint]
    /// Brush radius as a fraction of the photo's longest side.
    public var radius: CGFloat
    /// true removes (makes background), false restores (makes item).
    public var erase: Bool
    /// Smart brush: the colour (sRGB, 0...255) sampled where the stroke began. Only pixels close
    /// to it are changed, so a stroke along an edge stops at the edge. nil: a plain brush.
    public var reference: [UInt8]?
    /// How far (in sRGB units) a colour may be from the reference and still be fully painted.
    public var tolerance: Float

    public init(points: [CGPoint], radius: CGFloat, erase: Bool, reference: [UInt8]? = nil, tolerance: Float = 0) {
        self.points = points; self.radius = radius; self.erase = erase
        self.reference = reference; self.tolerance = tolerance
    }
}

public enum Brush {
    /// Default smart-brush tolerance.
    public static let smartTolerance: Float = 34

    /// Colour test for the smart brush, at one resolution.
    public struct Gate {
        public let pixels: [UInt8]
        public let width: Int
        public let reference: (Float, Float, Float)
        public let tolerance: Float

        public init?(photo: RGBAImage?, stroke: BrushStroke) {
            guard let photo, let r = stroke.reference, r.count >= 3 else { return nil }
            pixels = photo.pixels; width = photo.width
            reference = (Float(r[0]), Float(r[1]), Float(r[2]))
            tolerance = max(1, stroke.tolerance)
        }

        /// 1 for colours within the tolerance, fading to 0 at 1.6 times it.
        @inline(__always) func weight(_ i: Int) -> CGFloat {
            let p = i * 4
            let r = Float(pixels[p]), g = Float(pixels[p + 1]), b = Float(pixels[p + 2])
            // "Redmean" distance: close to perceived difference, and cheap.
            let rm = (r + reference.0) / 2
            let dr = r - reference.0, dg = g - reference.1, db = b - reference.2
            let d = sqrtf((2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db) / 3
            if d <= tolerance { return 1 }
            let f = 1 - (d - tolerance) / (0.6 * tolerance)
            return CGFloat(max(0, f))
        }
    }

    /// Average colour in a small disc (pixels), for the smart brush's reference.
    public static func sample(_ photo: RGBAImage, at c: CGPoint, radius: CGFloat) -> [UInt8] {
        let r = max(1, radius)
        let x0 = max(0, Int(c.x - r)), x1 = min(photo.width - 1, Int(c.x + r))
        let y0 = max(0, Int(c.y - r)), y1 = min(photo.height - 1, Int(c.y + r))
        guard x0 <= x1, y0 <= y1 else { return [128, 128, 128] }
        var s = (0, 0, 0), n = 0
        for y in y0...y1 {
            for x in x0...x1 where hypot(CGFloat(x) + 0.5 - c.x, CGFloat(y) + 0.5 - c.y) <= r {
                let p = (y * photo.width + x) * 4
                s.0 += Int(photo.pixels[p]); s.1 += Int(photo.pixels[p + 1]); s.2 += Int(photo.pixels[p + 2])
                n += 1
            }
        }
        guard n > 0 else { return [128, 128, 128] }
        return [UInt8(s.0 / n), UInt8(s.1 / n), UInt8(s.2 / n)]
    }

    /// Applies strokes to an alpha matte in place. The brush has a soft one-pixel rim.
    /// `photo` (the same size as the matte) is needed for smart strokes; without it they paint plainly.
    public static func apply(_ strokes: [BrushStroke], to alpha: inout [UInt8], width w: Int, height h: Int, photo: RGBAImage? = nil) {
        let L = CGFloat(max(w, h))
        let usable = photo.flatMap { $0.width == w && $0.height == h ? $0 : nil }
        for s in strokes {
            let r = max(1, s.radius * L)
            let gate = Gate(photo: usable, stroke: s)
            let pts = s.points.map { CGPoint(x: $0.x * CGFloat(w), y: $0.y * CGFloat(h)) }
            guard let first = pts.first else { continue }
            // The same sequence the live touch-up paints: a dab where the stroke starts, then each piece.
            _ = segment(&alpha, w, h, from: first, to: first, radius: r, erase: s.erase, gate: gate)
            for k in pts.indices.dropFirst() {
                _ = segment(&alpha, w, h, from: pts[k - 1], to: pts[k], radius: r, erase: s.erase, gate: gate)
            }
        }
    }

    /// Paints one straight piece of a stroke (pixel coordinates). Returns the rectangle changed.
    @discardableResult
    public static func segment(_ alpha: inout [UInt8], _ w: Int, _ h: Int, from a: CGPoint, to b: CGPoint,
                               radius r: CGFloat, erase: Bool, gate: Gate?) -> CGRect {
        let dist = hypot(b.x - a.x, b.y - a.y)
        let steps = max(1, Int(dist / max(1, r * 0.3)))
        alpha.withUnsafeMutableBufferPointer { buf in
            for t in 0...steps {
                let f = CGFloat(t) / CGFloat(steps)
                dab(buf, w, h, a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, r, erase, gate)
            }
        }
        return CGRect(x: min(a.x, b.x) - r - 2, y: min(a.y, b.y) - r - 2,
                      width: abs(b.x - a.x) + 2 * r + 4, height: abs(b.y - a.y) + 2 * r + 4)
    }

    private static func dab(_ alpha: UnsafeMutableBufferPointer<UInt8>, _ w: Int, _ h: Int, _ cx: CGFloat, _ cy: CGFloat,
                            _ r: CGFloat, _ erase: Bool, _ gate: Gate?) {
        let x0 = max(0, Int(cx - r - 1)), x1 = min(w - 1, Int(cx + r + 1))
        let y0 = max(0, Int(cy - r - 1)), y1 = min(h - 1, Int(cy + r + 1))
        guard x0 <= x1, y0 <= y1 else { return }
        let target: CGFloat = erase ? 0 : 255
        for y in y0...y1 {
            for x in x0...x1 {
                let d = hypot(CGFloat(x) + 0.5 - cx, CGFloat(y) + 0.5 - cy)
                var cover = min(1, max(0, r - d + 0.5))
                if cover <= 0 { continue }
                let i = y * w + x
                if let gate {
                    cover *= gate.weight(i)
                    if cover <= 0 { continue }
                }
                let v = CGFloat(alpha[i])
                // A smart stroke only moves alpha towards its target, never past what it gives.
                let nv = v + (target - v) * cover
                alpha[i] = UInt8(max(0, min(255, nv.rounded())))
            }
        }
    }
}
