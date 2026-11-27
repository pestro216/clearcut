import Foundation

/// Objective measures of a matte against a reference ("ground truth") matte.
public struct MatteScores: Codable {
    /// Intersection over union of the item (alpha > 0.5). 1 is perfect.
    public var iou: Double
    /// Boundary F-measure within 2 px at full resolution. 1 is perfect.
    public var boundaryF: Double
    /// Mean absolute alpha error inside the edge band (0...1). 0 is perfect.
    public var bandMAE: Double
    /// Share of the reference item's pixels missing from the result (cut into the product).
    public var missedItem: Double
    /// Background pixels kept, as a share of the item's size (leftover background).
    public var keptBackground: Double
    /// Mean colour error (CIE ΔE76) of the edge band when composited on a new backdrop,
    /// result against reference. Captures halos and old-background tint. Lower is better.
    public var edgeDeltaE: Double
    /// 95th percentile of the same: the worst visible edge spots.
    public var edgeDeltaE95: Double
    /// Gradient error (Rhemann et al. 2009, as in the Deep Image Matting evaluation): squared
    /// difference of alpha gradient magnitudes (Gaussian derivative, sigma 1.4), summed, / 1000.
    /// Rises when edges are blurrier (feathered) or noisier than the truth. Lower is better.
    public var gradient: Double?
    /// Connectivity error (same source): penalises parts of the matte cut off from the solid item,
    /// such as blotches and holes inside it. Summed, / 1000. Lower is better.
    public var connectivity: Double?
}

public enum Metrics {

    public static func score(alpha: [UInt8], reference: [UInt8], width w: Int, height h: Int,
                             photo: RGBAImage, foreground: RGBAImage, referenceForeground: RGBAImage,
                             testBackdrop: RGBAImage) -> MatteScores {
        let n = w * h
        var inter = 0, uni = 0, refCount = 0, missed = 0, kept = 0
        for i in 0..<n {
            let a = alpha[i] > 127, r = reference[i] > 127
            if a && r { inter += 1 }
            if a || r { uni += 1 }
            if r { refCount += 1; if !a { missed += 1 } } else if a { kept += 1 }
        }
        let iou = uni == 0 ? 1 : Double(inter) / Double(uni)

        // Boundaries.
        let bA = boundary(alpha, w, h), bR = boundary(reference, w, h)
        let tol = 2
        let dA = dilate(bA, w, h, tol), dR = dilate(bR, w, h, tol)
        var tpP = 0, nA = 0, tpR = 0, nR = 0
        for i in 0..<n {
            if bA[i] { nA += 1; if dR[i] { tpP += 1 } }
            if bR[i] { nR += 1; if dA[i] { tpR += 1 } }
        }
        let precision = nA == 0 ? 0 : Double(tpP) / Double(nA)
        let recall = nR == 0 ? 0 : Double(tpR) / Double(nR)
        let bf = precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall)

        // Edge band: within 6 px of the reference boundary.
        let band = dilate(bR, w, h, 6)
        var sad = 0.0, bandN = 0
        var deltas: [Double] = []
        for i in 0..<n where band[i] {
            bandN += 1
            sad += abs(Double(alpha[i]) - Double(reference[i])) / 255
            let ours = blend(foreground, alpha[i], testBackdrop, i)
            let truth = blend(referenceForeground, reference[i], testBackdrop, i)
            deltas.append(deltaE(ours, truth))
        }
        deltas.sort()
        let meanDE = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count)
        let p95 = deltas.isEmpty ? 0 : deltas[min(deltas.count - 1, Int(Double(deltas.count) * 0.95))]
        return MatteScores(iou: iou, boundaryF: bf, bandMAE: bandN == 0 ? 0 : sad / Double(bandN),
                           missedItem: refCount == 0 ? 0 : Double(missed) / Double(refCount),
                           keptBackground: refCount == 0 ? 0 : Double(kept) / Double(refCount),
                           edgeDeltaE: meanDE, edgeDeltaE95: p95,
                           gradient: gradientError(alpha, reference, w, h),
                           connectivity: connectivityError(alpha, reference, w, h))
    }

    /// Gradient error / 1000. Both mattes are differentiated with first-order Gaussian derivative
    /// filters (sigma 1.4), and the squared differences of gradient magnitude are summed.
    static func gradientError(_ a: [UInt8], _ r: [UInt8], _ w: Int, _ h: Int) -> Double {
        let sigma: Float = 1.4, rad = Int((3 * sigma).rounded(.up))
        var g = [Float](repeating: 0, count: 2 * rad + 1), dg = g
        var gs: Float = 0, ds: Float = 0
        for k in -rad...rad {
            let x = Float(k), e = expf(-x * x / (2 * sigma * sigma))
            g[k + rad] = e; gs += e
            dg[k + rad] = -x * e; ds += abs(x * e)
        }
        for k in 0..<g.count { g[k] /= gs; dg[k] /= ds / 2 }
        func conv(_ src: [Float], _ kx: [Float], _ ky: [Float]) -> [Float] {
            var tmp = [Float](repeating: 0, count: w * h), out = tmp
            for y in 0..<h { for x in 0..<w {
                var s: Float = 0
                for k in -rad...rad { s += src[y * w + min(w - 1, max(0, x + k))] * kx[k + rad] }
                tmp[y * w + x] = s
            } }
            for y in 0..<h { for x in 0..<w {
                var s: Float = 0
                for k in -rad...rad { s += tmp[min(h - 1, max(0, y + k)) * w + x] * ky[k + rad] }
                out[y * w + x] = s
            } }
            return out
        }
        func magnitude(_ m: [UInt8]) -> [Float] {
            let f = m.map { Float($0) / 255 }
            let gx = conv(f, dg, g), gy = conv(f, g, dg)
            return zip(gx, gy).map { sqrtf($0 * $0 + $1 * $1) }
        }
        let ma = magnitude(a), mr = magnitude(r)
        var e: Double = 0
        for i in 0..<(w * h) { let d = Double(ma[i] - mr[i]); e += d * d }
        return e / 1000
    }

    /// Connectivity error / 1000. For thresholds 0, 0.1 ... 1, the largest region where both
    /// mattes reach the threshold is the solid core; each pixel's level is the last threshold at
    /// which it still belonged to that core. Pixels whose alpha rises well above their level
    /// (disconnected from the core) are penalised, and the two mattes' penalties are compared.
    static func connectivityError(_ a: [UInt8], _ r: [UInt8], _ w: Int, _ h: Int) -> Double {
        let n = w * h
        let fa = a.map { Float($0) / 255 }, fr = r.map { Float($0) / 255 }
        var level = [Float](repeating: -1, count: n)
        let step: Float = 0.1
        var t: Float = 0
        while t <= 1.0001 {
            var both = [Bool](repeating: false, count: n)
            for i in 0..<n { both[i] = fa[i] >= t && fr[i] >= t }
            let (lab, sz) = Regions.label(both, width: w, height: h)
            var biggest = 0, best = 0
            for l in 1..<max(1, sz.count) where sz[l] > biggest { biggest = sz[l]; best = l }
            for i in 0..<n where level[i] == -1 && (best == 0 || Int(lab[i]) != best) { level[i] = t - step }
            t += step
        }
        for i in 0..<n where level[i] == -1 { level[i] = 1 }
        var e: Double = 0
        for i in 0..<n {
            let da = fa[i] - level[i], dr = fr[i] - level[i]
            let pa: Float = da >= 0.15 ? 1 - da : 1, pr: Float = dr >= 0.15 ? 1 - dr : 1
            e += Double(abs(pa - pr))
        }
        return e / 1000
    }

    static func boundary(_ a: [UInt8], _ w: Int, _ h: Int) -> [Bool] {
        var b = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let v = a[i] > 127
                if x + 1 < w && (a[i + 1] > 127) != v { b[i] = true; b[i + 1] = true }
                if y + 1 < h && (a[i + w] > 127) != v { b[i] = true; b[i + w] = true }
            }
        }
        return b
    }

    static func dilate(_ m: [Bool], _ w: Int, _ h: Int, _ r: Int) -> [Bool] {
        // Separable square dilation.
        var tmp = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            var last = -10_000_000
            for x in 0..<w { if m[y * w + x] { last = x }; if x - last <= r { tmp[y * w + x] = true } }
            last = 10_000_000
            for x in stride(from: w - 1, through: 0, by: -1) { if m[y * w + x] { last = x }; if last - x <= r { tmp[y * w + x] = true } }
        }
        var out = [Bool](repeating: false, count: w * h)
        for x in 0..<w {
            var last = -10_000_000
            for y in 0..<h { if tmp[y * w + x] { last = y }; if y - last <= r { out[y * w + x] = true } }
            last = 10_000_000
            for y in stride(from: h - 1, through: 0, by: -1) { if tmp[y * w + x] { last = y }; if last - y <= r { out[y * w + x] = true } }
        }
        return out
    }

    static func blend(_ f: RGBAImage, _ a: UInt8, _ bg: RGBAImage, _ i: Int) -> (Double, Double, Double) {
        let af = Double(a) / 255
        func ch(_ c: Int) -> Double {
            let lf = Double(Linear.toLinear[Int(f.pixels[i * 4 + c])]), lb = Double(Linear.toLinear[Int(bg.pixels[i * 4 + c])])
            return lf * af + lb * (1 - af)
        }
        return (ch(0), ch(1), ch(2))
    }

    /// CIE76 ΔE between two linear-sRGB colours.
    static func deltaE(_ p: (Double, Double, Double), _ q: (Double, Double, Double)) -> Double {
        let a = lab(p), b = lab(q)
        return sqrt((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2))
    }

    static func lab(_ c: (Double, Double, Double)) -> (Double, Double, Double) {
        let X = 0.4124 * c.0 + 0.3576 * c.1 + 0.1805 * c.2
        let Y = 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
        let Z = 0.0193 * c.0 + 0.1192 * c.1 + 0.9505 * c.2
        func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1.0 / 3.0) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(X / 0.95047), fy = f(Y), fz = f(Z / 1.08883)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
}

/// Measures that need no reference matte, for real photos.
public struct BlindScores: Codable {
    /// Share of the photo the item covers.
    public var area: Double
    /// Share of edge pixels that are partially transparent (high = soft/feathered edge).
    public var softEdgeShare: Double
    /// Mean width of the alpha transition across the outline, in pixels.
    public var edgeWidthPx: Double
    /// Number of separate pieces in the cutout.
    public var pieces: Int
}

extension Metrics {
    public static func blind(alpha: [UInt8], width w: Int, height h: Int) -> BlindScores {
        let n = w * h
        var on = 0, partial = 0
        for i in 0..<n { if alpha[i] > 127 { on += 1 }; if alpha[i] > 8 && alpha[i] < 247 { partial += 1 } }
        let b = boundary(alpha, w, h)
        let bCount = b.reduce(0) { $0 + ($1 ? 1 : 0) }
        let bandMask = dilate(b, w, h, 8)
        var bandPartial = 0, bandN = 0
        for i in 0..<n where bandMask[i] { bandN += 1; if alpha[i] > 8 && alpha[i] < 247 { bandPartial += 1 } }
        let pieces = Regions.label(alpha.map { $0 > 127 }, width: w, height: h).sizes.dropFirst().filter { $0 > n / 5000 }.count
        return BlindScores(area: Double(on) / Double(n),
                           softEdgeShare: bandN == 0 ? 0 : Double(bandPartial) / Double(bandN),
                           edgeWidthPx: bCount == 0 ? 0 : Double(partial) / (Double(bCount) / 2),
                           pieces: pieces)
    }
}
