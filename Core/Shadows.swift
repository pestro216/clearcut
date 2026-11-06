import Foundation
import Accelerate

public enum ShadowKind: String, CaseIterable, Codable, Identifiable {
    case flatlay, lifted, none
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .flatlay: return "Flatlay"
        case .lifted: return "Lifted"
        case .none: return "None"
        }
    }
}

public struct ShadowParams: Codable, Hashable {
    public var kind: ShadowKind = .flatlay
    /// 0...1, default tuned for a soft overhead softbox.
    public var strength: Float = 0.6
    /// Direction the shadow falls, degrees: 0 right, 90 down, 180 left, 270 up.
    public var angle: Float = 100

    public init(kind: ShadowKind = .flatlay, strength: Float = 0.6, angle: Float = 100) {
        self.kind = kind; self.strength = strength; self.angle = angle
    }
}

/// Shadow density (0 none ... 1 black) for a product lying on a surface, lit from above.
///
/// Built from the item's own outline, in three parts that a real overhead light produces:
/// - Contact: a tight, dark occlusion right where the item meets the surface, at full resolution.
/// - Cast: the item's body offset away from the light and softened. Its height is estimated from
///   the outline (distance from the edge), so thin parts such as straps and edges cast short,
///   crisp shadows and thick parts cast longer, softer ones.
/// - Ambient: a faint, wide occlusion that settles the item into the surface.
/// Sizes scale with the photo, so the same setting suits every photo in a batch.
public enum ShadowModel {

    public static func density(alpha: [UInt8], width fw: Int, height fh: Int, params: ShadowParams) -> Plane? {
        guard params.kind != .none, params.strength > 0 else { return nil }
        let L = Float(max(fw, fh))
        let rad = params.angle * .pi / 180
        let dx = cos(rad), dy = sin(rad)           // image coordinates, y down
        let lifted = params.kind == .lifted

        // Low-resolution copy for the broad components.
        let k = min(1, 1024 / L)
        let lw = max(8, Int(Float(fw) * k)), lh = max(8, Int(Float(fh) * k))
        let a = Plane(bytes: alpha, width: fw, height: fh)
        let aLow = a.resized(width: lw, height: lh)
        let lowScale = Float(lw) / Float(fw)

        // Height proxy from the distance to the outline, saturating at a typical product thickness.
        let dist = distanceInside(aLow)
        let hCap = 0.03 * L * lowScale
        let height = dist.map { min(1, $0 / max(1, hCap)) }

        // Cast component: four height bands, each shifted and blurred more the higher it sits.
        let offsetMax = (lifted ? 0.030 : 0.009) * L * lowScale
        let blurBase = (lifted ? 0.010 : 0.002) * L * lowScale
        let blurMax = (lifted ? 0.030 : 0.014) * L * lowScale
        var cast = Plane(width: lw, height: lh, value: 0)
        let bands: [Float] = [0.25, 0.5, 0.75, 1.0]
        for level in bands {
            let band = Plane.combine(height, aLow) { hh, av in
                let t = (hh - (level - 0.25)) / 0.25
                return av * (t < 0 ? 0 : (t > 1 ? 1 : t * t * (3 - 2 * t)))
            }
            let off = (lifted ? 0.35 : 0.1) * offsetMax + level * offsetMax * (lifted ? 0.65 : 0.9)
            let blurred = band.gaussianBlurred(sigma: blurBase + level * blurMax).shifted(dx: dx * off, dy: dy * off)
            let weight: Float = lifted ? 0.28 : 0.30
            cast = Plane.combine(cast, blurred) { c, b in 1 - (1 - c) * (1 - weight * b) }
        }
        let ambient = aLow.gaussianBlurred(sigma: 0.022 * L * lowScale).map { $0 * (lifted ? 0.12 : 0.18) }

        // Contact component at full resolution.
        var contact: Plane?
        if !lifted {
            let sigma = max(1, 0.0012 * L)
            let off = 0.0006 * L
            contact = a.gaussianBlurred(sigma: sigma).shifted(dx: dx * off, dy: dy * off).map { $0 * 0.55 }
        }

        let gain = min(1.6, params.strength * 1.45)
        var out = [Float](repeating: 0, count: fw * fh)
        let sx = Float(lw) / Float(fw), sy = Float(lh) / Float(fh)
        out.withUnsafeMutableBufferPointer { o in
            for y in 0..<fh {
                let fy = (Float(y) + 0.5) * sy
                for x in 0..<fw {
                    let fx = (Float(x) + 0.5) * sx
                    let i = y * fw + x
                    let c = cast.sample(fx, fy), amb = ambient.sample(fx, fy)
                    let con = contact?.data[i] ?? 0
                    let s = 1 - (1 - c) * (1 - amb) * (1 - con)
                    o[i] = min(0.92, s * gain)
                }
            }
        }
        return Plane(width: fw, height: fh, data: out)
    }

    /// Two-pass chamfer distance (in pixels) from each inside pixel to the outline.
    static func distanceInside(_ a: Plane) -> Plane {
        let w = a.width, h = a.height
        let big: Float = 1e6
        var d = a.data.map { $0 > 0.5 ? big : 0 }
        let c1: Float = 1, c2: Float = 1.4142
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if d[i] == 0 { continue }
                var v = d[i]
                if x > 0 { v = min(v, d[i - 1] + c1) }
                if y > 0 {
                    v = min(v, d[i - w] + c1)
                    if x > 0 { v = min(v, d[i - w - 1] + c2) }
                    if x < w - 1 { v = min(v, d[i - w + 1] + c2) }
                }
                d[i] = v
            }
        }
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) {
                let i = y * w + x
                if d[i] == 0 { continue }
                var v = d[i]
                if x < w - 1 { v = min(v, d[i + 1] + c1) }
                if y < h - 1 {
                    v = min(v, d[i + w] + c1)
                    if x < w - 1 { v = min(v, d[i + w + 1] + c2) }
                    if x > 0 { v = min(v, d[i + w - 1] + c2) }
                }
                d[i] = v
            }
        }
        // Pixels touching the frame edge would otherwise read as infinitely thick.
        return Plane(width: w, height: h, data: d.map { $0 >= big ? 0 : $0 })
    }
}

extension Plane {
    /// Moves content by (dx, dy) pixels, bilinear, filling with zero.
    public func shifted(dx: Float, dy: Float) -> Plane {
        if abs(dx) < 0.01 && abs(dy) < 0.01 { return self }
        var out = [Float](repeating: 0, count: count)
        for y in 0..<height {
            let sy = Float(y) - dy + 0.5
            if sy < 0 || sy > Float(height) { continue }
            for x in 0..<width {
                let sx = Float(x) - dx + 0.5
                if sx < 0 || sx > Float(width) { continue }
                out[y * width + x] = sample(sx, sy)
            }
        }
        return Plane(width: width, height: height, data: out)
    }
}
