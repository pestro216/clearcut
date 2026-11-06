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

    public init(points: [CGPoint], radius: CGFloat, erase: Bool) {
        self.points = points; self.radius = radius; self.erase = erase
    }
}

public enum Brush {
    /// Applies strokes to an alpha matte in place. The brush has a soft one-pixel rim.
    public static func apply(_ strokes: [BrushStroke], to alpha: inout [UInt8], width w: Int, height h: Int) {
        let L = CGFloat(max(w, h))
        for s in strokes {
            let r = max(1, s.radius * L)
            var pts = s.points.map { CGPoint(x: $0.x * CGFloat(w), y: $0.y * CGFloat(h)) }
            if pts.count == 1 { pts.append(pts[0]) }
            for k in 1..<pts.count {
                let a = pts[k - 1], b = pts[k]
                let dist = hypot(b.x - a.x, b.y - a.y)
                let steps = max(1, Int(dist / max(1, r * 0.3)))
                for t in 0...steps {
                    let f = CGFloat(t) / CGFloat(steps)
                    dab(&alpha, w, h, a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, r, s.erase)
                }
            }
        }
    }

    private static func dab(_ alpha: inout [UInt8], _ w: Int, _ h: Int, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ erase: Bool) {
        let x0 = max(0, Int(cx - r - 1)), x1 = min(w - 1, Int(cx + r + 1))
        let y0 = max(0, Int(cy - r - 1)), y1 = min(h - 1, Int(cy + r + 1))
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                let d = hypot(CGFloat(x) + 0.5 - cx, CGFloat(y) + 0.5 - cy)
                let cover = min(1, max(0, r - d + 0.5))
                if cover <= 0 { continue }
                let i = y * w + x
                let v = CGFloat(alpha[i])
                let target: CGFloat = erase ? 0 : 255
                alpha[i] = UInt8(max(0, min(255, (v + (target - v) * cover).rounded())))
            }
        }
    }
}
