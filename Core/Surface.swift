import Foundation

/// What the surface under the item looks like: a handful of colour clusters (a grey carpet, its
/// darker flecks, a cream wall at the top of the frame), each with its own spread.
///
/// Clearcut learns this from photos where Apple's model clearly separates item and surface, and
/// keeps it for the rest of the batch (and between launches). With it, the engine can tell
/// "carpet" from "not carpet" anywhere in a photo, which is what close-ups and linings need:
/// Apple's model looks for a subject, while a flatlay only needs to know what the surface is.
///
/// Colours are compared as brightness plus brightness-independent tint, so the surface in the
/// item's shadow still counts as surface; very much darker pixels do not, so black items don't.
public struct SurfaceModel: Codable, Equatable, Sendable {
    public var means: [[Float]]
    public var invCov: [[Float]]
    public var weights: [Float]
    /// Distances (squared, Mahalanobis) below `low` are typical surface; above `high`, not surface.
    public var low: Float
    public var high: Float

    // MARK: Features

    @inline(__always)
    static func features(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let l = (r + g + b) / 3
        let d = l + 0.06
        return (l, (r - g) / d, ((r + g) / 2 - b) / d)
    }

    /// Squared distance of a colour (0...1 sRGB) from the nearest cluster.
    @inline(__always)
    public func distance(_ r: Float, _ g: Float, _ b: Float) -> Float {
        let f = SurfaceModel.features(r, g, b)
        var best = Float.greatestFiniteMagnitude
        for k in 0..<means.count {
            let m = means[k], ic = invCov[k]
            var d0 = f.0 - m[0]
            if d0 < 0 {
                // In shadow the surface gets darker without changing tint. Allow down to 55% of
                // its brightness at a small cost; beyond that, darkness counts in full.
                let floor = m[0] * 0.55
                d0 = f.0 >= floor ? d0 * 0.3 : (floor - f.0) + (floor - m[0]) * 0.3
            }
            let d1 = f.1 - m[1], d2 = f.2 - m[2]
            let q = d0 * (ic[0] * d0 + ic[1] * d1 + ic[2] * d2)
                + d1 * (ic[3] * d0 + ic[4] * d1 + ic[5] * d2)
                + d2 * (ic[6] * d0 + ic[7] * d1 + ic[8] * d2)
            if q < best { best = q }
        }
        return best
    }

    // MARK: Fitting

    /// Fits clusters to sample colours (sRGB 0...1). Returns nil with too few samples.
    public static func fit(r: [Float], g: [Float], b: [Float], clusters kWanted: Int = 5) -> SurfaceModel? {
        let n = r.count
        guard n >= 200 else { return nil }
        var f = [(Float, Float, Float)](repeating: (0, 0, 0), count: n)
        for i in 0..<n { f[i] = features(r[i], g[i], b[i]) }
        let k = min(kWanted, max(1, n / 100))

        // Deterministic k-means++ style seeding: spread seeds by brightness order, then refine.
        let order = (0..<n).sorted { f[$0].0 < f[$1].0 }
        var centres = (0..<k).map { j -> (Float, Float, Float) in f[order[min(n - 1, (2 * j + 1) * n / (2 * k))]] }
        var assign = [Int](repeating: 0, count: n)
        for _ in 0..<10 {
            for i in 0..<n {
                var best = Float.greatestFiniteMagnitude, bj = 0
                for j in 0..<k {
                    let a = f[i].0 - centres[j].0, c1 = (f[i].1 - centres[j].1) * 0.5, c2 = (f[i].2 - centres[j].2) * 0.5
                    let d = a * a + c1 * c1 + c2 * c2
                    if d < best { best = d; bj = j }
                }
                assign[i] = bj
            }
            var sum = [(Float, Float, Float)](repeating: (0, 0, 0), count: k), cnt = [Int](repeating: 0, count: k)
            for i in 0..<n {
                let j = assign[i]
                sum[j].0 += f[i].0; sum[j].1 += f[i].1; sum[j].2 += f[i].2; cnt[j] += 1
            }
            for j in 0..<k where cnt[j] > 0 {
                let c = Float(cnt[j])
                centres[j] = (sum[j].0 / c, sum[j].1 / c, sum[j].2 / c)
            }
        }

        var means: [[Float]] = [], invs: [[Float]] = [], weights: [Float] = []
        for j in 0..<k {
            let idx = (0..<n).filter { assign[$0] == j }
            if Float(idx.count) < 0.02 * Float(n) || idx.count < 20 { continue }
            let m = centres[j]
            var c = [Float](repeating: 0, count: 9)
            for i in idx {
                let d = [f[i].0 - m.0, f[i].1 - m.1, f[i].2 - m.2]
                for a in 0..<3 { for bb in 0..<3 { c[a * 3 + bb] += d[a] * d[bb] } }
            }
            let cn = Float(idx.count)
            for a in 0..<9 { c[a] /= cn }
            // Floor the spread: JPEG noise and lighting variation are always there.
            c[0] += 0.0004; c[4] += 0.0016; c[8] += 0.0016
            guard let inv = invert3(c) else { continue }
            means.append([m.0, m.1, m.2]); invs.append(inv); weights.append(cn / Float(n))
        }
        guard !means.isEmpty else { return nil }
        var model = SurfaceModel(means: means, invCov: invs, weights: weights, low: 0, high: 0)
        // Calibrate the thresholds on the samples themselves.
        var ds = (0..<n).map { model.distance(r[$0], g[$0], b[$0]) }
        ds.sort()
        model.low = max(3, ds[Int(Float(n - 1) * 0.80)])
        model.high = max(16, ds[Int(Float(n - 1) * 0.995)] * 1.5)
        return model
    }

    /// The same surface photographed brighter or darker, or under slightly different light.
    public func adjusted(gain: Float, tint1: Float, tint2: Float) -> SurfaceModel {
        var m = self
        m.means = means.map { [$0[0] * gain, $0[1] + tint1, $0[2] + tint2] }
        return m
    }

    static func invert3(_ s: [Float]) -> [Float]? {
        let c11 = s[4] * s[8] - s[5] * s[7], c12 = s[2] * s[7] - s[1] * s[8], c13 = s[1] * s[5] - s[2] * s[4]
        let c21 = s[5] * s[6] - s[3] * s[8], c22 = s[0] * s[8] - s[2] * s[6], c23 = s[2] * s[3] - s[0] * s[5]
        let c31 = s[3] * s[7] - s[4] * s[6], c32 = s[1] * s[6] - s[0] * s[7], c33 = s[0] * s[4] - s[1] * s[3]
        let det = s[0] * c11 + s[1] * c21 + s[2] * c31
        guard abs(det) > 1e-14 else { return nil }
        let k = 1 / det
        return [c11 * k, c12 * k, c13 * k, c21 * k, c22 * k, c23 * k, c31 * k, c32 * k, c33 * k]
    }
}

/// Surface and item colour maps for one photo at working resolution.
struct SurfaceMaps {
    /// Share of nearby pixels that look like typical surface / clearly not surface.
    var surfaceShare: Plane
    var otherShare: Plane
    /// Share of surface over a wider area (about 1% of the photo across): decides regions, so a
    /// patterned item whose plain squares happen to match the surface is still seen as item.
    var coarseSurface: Plane
    var coarseRadius: Int
    /// Per-pixel: also unlike the item (only when an item model exists).
    var unlikeItem: [Bool]?
    var model: SurfaceModel
    var itemModel: SurfaceModel?
}

enum SurfaceAnalysis {
    /// Samples (sRGB) where the mask is true, at most `limit`, evenly spread.
    static func samples(_ R: Plane, _ G: Plane, _ B: Plane, where mask: [Bool], limit: Int = 30000) -> ([Float], [Float], [Float]) {
        let total = mask.reduce(0) { $0 + ($1 ? 1 : 0) }
        guard total > 0 else { return ([], [], []) }
        let step = max(1, total / limit)
        var r: [Float] = [], g: [Float] = [], b: [Float] = []
        r.reserveCapacity(min(total, limit) + 1); g.reserveCapacity(r.capacity); b.reserveCapacity(r.capacity)
        var k = 0
        for i in 0..<mask.count where mask[i] {
            if k % step == 0 { r.append(R.data[i]); g.append(G.data[i]); b.append(B.data[i]) }
            k += 1
        }
        return (r, g, b)
    }

    static func maps(R: Plane, G: Plane, B: Plane, model: SurfaceModel, itemModel: SurfaceModel?, longSide: Float) -> SurfaceMaps {
        let w = R.width, h = R.height, n = w * h
        // Light smoothing first: carpet and weave texture is finer than anything we decide on.
        let r = R.gaussianBlurred(sigma: 1.0), g = G.gaussianBlurred(sigma: 1.0), b = B.gaussianBlurred(sigma: 1.0)
        var surf = [Float](repeating: 0, count: n), other = [Float](repeating: 0, count: n)
        var unlike: [Bool]? = itemModel == nil ? nil : [Bool](repeating: false, count: n)
        for i in 0..<n {
            let d = model.distance(r.data[i], g.data[i], b.data[i])
            if d < model.low { surf[i] = 1 } else if d > model.high { other[i] = 1 }
            if let im = itemModel { unlike![i] = im.distance(r.data[i], g.data[i], b.data[i]) > im.high }
        }
        let rad = max(2, Int(0.004 * longSide))
        let coarse = max(4, Int(0.012 * longSide))
        let surfPlane = Plane(width: w, height: h, data: surf)
        return SurfaceMaps(surfaceShare: surfPlane.boxBlurred(radius: rad),
                           otherShare: Plane(width: w, height: h, data: other).boxBlurred(radius: rad),
                           coarseSurface: surfPlane.boxBlurred(radius: coarse), coarseRadius: coarse,
                           unlikeItem: unlike, model: model, itemModel: itemModel)
    }

    /// Fits the batch's surface to this photo's exposure and light: tries a range of brightness
    /// and small tint shifts and keeps the one under which most of the photo looks like surface.
    static func adapt(_ prior: SurfaceModel, R: Plane, G: Plane, B: Plane) -> (SurfaceModel, Float) {
        let n = R.count
        var idx: [Int] = []
        let step = max(1, n / 40000)
        var i = 0
        while i < n { idx.append(i); i += step }
        var best = prior, bestCov: Float = -1
        for gain: Float in [0.72, 0.8, 0.88, 0.96, 1.04, 1.12, 1.2, 1.3, 1.4] {
            for t1: Float in [-0.05, 0, 0.05] {
                for t2: Float in [-0.05, 0, 0.05] {
                    let m = prior.adjusted(gain: gain, tint1: t1, tint2: t2)
                    var c = 0
                    for j in idx where m.distance(R.data[j], G.data[j], B.data[j]) < m.low { c += 1 }
                    // Prefer the unshifted surface when it does as well.
                    let cov = Float(c) / Float(idx.count) - (t1 == 0 && t2 == 0 ? 0 : 0.003) - abs(gain - 1) * 0.004
                    if cov > bestCov { bestCov = cov; best = m }
                }
            }
        }
        return (best, max(0, bestCov))
    }

    /// Share of the photo that looks like the given surface.
    static func coverage(R: Plane, G: Plane, B: Plane, model: SurfaceModel) -> Float {
        let n = R.count
        var c = 0, t = 0
        for i in stride(from: 0, to: n, by: 5) {
            if model.distance(R.data[i], G.data[i], B.data[i]) < model.low { c += 1 }
            t += 1
        }
        return Float(c) / Float(max(1, t))
    }
}
