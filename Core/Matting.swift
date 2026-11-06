import Foundation
import Accelerate

/// How sure Clearcut is about a cutout.
public enum Confidence: Equatable {
    case good
    case check(String)
    case failed(String)

    public var needsAttention: Bool {
        if case .good = self { return false }
        return true
    }
}

public struct Matte {
    public var width: Int
    public var height: Int
    /// Full-resolution alpha, 0 background ... 255 item.
    public var alpha: [UInt8]
    public var confidence: Confidence
    /// Diagnostics for the quality report.
    public var notes: [String: Double]
}

public struct MatteOptions {
    /// Use the photo's own colours to recover parts the model missed and remove background it kept.
    public var colourEvidence = true
    /// Edge-aware refinement against the full-resolution photo.
    public var guidedRefinement = true
    /// Guided filter radius in working-resolution pixels.
    public var guidedRadius = 5
    /// Guided filter regulariser (smaller follows image edges more closely).
    public var guidedEps: Float = 0.0025
    /// Values below/above these become fully clear/opaque. A light clean-up, not a steepening.
    public var levelsLow: Float = 0.03
    public var levelsHigh: Float = 0.97

    public init() {}
}

/// Turns the model's coarse probability into an accurate full-resolution alpha matte.
///
/// 1. Remove stray islands the model picked up.
/// 2. Where the item stands clearly apart from a fairly even background, use colour evidence
///    to add back parts the model missed (thin straps, protrusions) and take out background
///    it kept (gaps, holes). Shadows on the background are recognised and left out.
///    When the item and background are too alike (light on light, dark on dark) this step
///    switches itself off rather than guess.
/// 3. Snap the outline to the real edges of the full-resolution photo with a colour guided
///    filter (He et al.), computed at working resolution and applied at full resolution.
///    Soft, genuine transitions survive; nothing is artificially steepened or choked.
public enum Matting {

    public static func refine(full: RGBAImage, segmentation seg: Segmentation, options: MatteOptions = MatteOptions()) -> Matte {
        let ww = seg.prob.width, wh = seg.prob.height, n = ww * wh
        let longW = Float(max(ww, wh))
        var notes: [String: Double] = [:]
        var flags: [String] = []
        notes["instances"] = Double(seg.instanceCount)
        notes["zoomed"] = seg.zoomed ? 1 : 0

        let guide = full.resized(width: ww, height: wh)
        let R = guide.channel(0), G = guide.channel(1), B = guide.channel(2)
        var p = seg.prob

        // 1. Islands: keep components at least 4% the size of the largest.
        var fg = p.data.map { $0 > 0.5 }
        let (labels, sizes) = Regions.label(fg, width: ww, height: wh)
        let biggest = sizes.dropFirst().max() ?? 0
        if biggest == 0 {
            return Matte(width: full.width, height: full.height, alpha: [UInt8](repeating: 0, count: full.width * full.height),
                         confidence: .failed("No item found"), notes: notes)
        }
        var removedIslands = 0
        for i in 0..<n where fg[i] {
            if Float(sizes[Int(labels[i])]) < Float(biggest) * 0.04 { fg[i] = false; removedIslands += 1 }
        }
        if removedIslands > 0 {
            let keep = Plane(width: ww, height: wh, data: fg.map { $0 ? 1 : 0 }).boxBlurred(radius: 3)
            for i in 0..<n where keep.data[i] == 0 { p.data[i] = 0 }
        }
        notes["islandsRemovedPx"] = Double(removedIslands)
        let components = sizes.dropFirst().filter { Float($0) >= Float(biggest) * 0.04 }.count
        notes["components"] = Double(components)

        var fgArea = fg.reduce(0) { $0 + ($1 ? 1 : 0) }

        // 2. Colour evidence.
        if options.colourEvidence {
            let ev = colourEvidence(R: R, G: G, B: B, prob: &p, fg: &fg, longSide: longW, notes: &notes)
            if let warning = ev { flags.append(warning) }
            fgArea = fg.reduce(0) { $0 + ($1 ? 1 : 0) }
        }

        let areaFrac = Float(fgArea) / Float(n)
        notes["areaFraction"] = Double(areaFrac)

        // 3. Guided refinement, applied at full resolution.
        let alpha: [UInt8]
        if options.guidedRefinement {
            alpha = guidedUpsample(full: full, R: R, G: G, B: B, p: p, radius: options.guidedRadius, eps: options.guidedEps,
                                   low: options.levelsLow, high: options.levelsHigh)
        } else {
            let up = p.resized(width: full.width, height: full.height)
            alpha = levels(up, low: options.levelsLow, high: options.levelsHigh)
        }

        // Confidence.
        var confidence: Confidence = .good
        if areaFrac < 0.002 {
            confidence = .failed("The item is too small to cut out reliably")
        } else if areaFrac > 0.92 {
            confidence = .check("The item fills almost the whole frame")
        } else if let f = flags.first {
            confidence = .check(f)
        }
        return Matte(width: full.width, height: full.height, alpha: alpha, confidence: confidence, notes: notes)
    }

    // MARK: Colour evidence

    /// Returns a warning when the photo's colours disagree strongly with the model.
    private static func colourEvidence(R: Plane, G: Plane, B: Plane, prob p: inout Plane, fg: inout [Bool],
                                       longSide: Float, notes: inout [String: Double]) -> String? {
        let w = p.width, h = p.height, n = w * h
        let fgPlane = Plane(width: w, height: h, data: fg.map { $0 ? 1 : 0 })

        // Confident background: low probability and well away from the item.
        let nearR = max(2, Int(0.02 * longSide))
        let near = fgPlane.boxBlurred(radius: nearR)
        var bgW = [Float](repeating: 0, count: n)
        var bgCount = 0
        for i in 0..<n where p.data[i] < 0.03 && near.data[i] == 0 { bgW[i] = 1; bgCount += 1 }
        let bgFrac = Float(bgCount) / Float(n)
        notes["backgroundSampleFraction"] = Double(bgFrac)
        guard bgFrac > 0.08 else { notes["colourEvidence"] = 0; return nil }

        // Smooth background estimate everywhere (normalised convolution), follows lighting falloff.
        let sigma = 0.05 * longSide
        let wPlane = Plane(width: w, height: h, data: bgW)
        let den = wPlane.gaussianBlurred(sigma: sigma)
        func bgEstimate(_ c: Plane) -> Plane {
            let num = (c * wPlane).gaussianBlurred(sigma: sigma)
            return Plane.combine(num, den) { a, d in d > 1e-4 ? a / d : 0 }
        }
        let bR = bgEstimate(R), bG = bgEstimate(G), bB = bgEstimate(B)

        // Distance from the background, tolerant of shadows (darker, same hue).
        var D = [Float](repeating: 0, count: n)
        var shadowLike = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let r = R.data[i], g = G.data[i], b = B.data[i]
            let rb = bR.data[i], gb = bG.data[i], bb = bB.data[i]
            let dr = r - rb, dg = g - gb, db = b - bb
            let euclid = sqrt(dr * dr + dg * dg + db * db)
            let L = (r + g + b) / 3 + 0.004, Lb = (rb + gb + bb) / 3 + 0.004
            let ratio = L / Lb
            let cr = r / L - rb / Lb, cg = g / L - gb / Lb, cb = b / L - bb / Lb
            let chroma = sqrt(cr * cr + cg * cg + cb * cb) * 0.33 * min(1, min(L, Lb) / 0.15)
            if ratio > 0.15 && ratio < 1.04 && chroma < 0.06 {
                shadowLike[i] = true
                D[i] = chroma
            } else {
                D[i] = euclid
            }
        }

        // Background noise level (robust).
        var bgD: [Float] = []
        bgD.reserveCapacity(bgCount / 7 + 1)
        var k = 0
        for i in 0..<n where bgW[i] == 1 { if k % 7 == 0 { bgD.append(D[i]) }; k += 1 }
        let noise = max(0.012, median(bgD) * 1.4826)
        notes["backgroundNoise"] = Double(noise)

        // How clearly the item stands apart from the background.
        let core = fgPlane.boxBlurred(radius: 3)
        var coreZ: [Float] = []
        for i in stride(from: 0, to: n, by: 3) where core.data[i] >= 0.999 { coreZ.append(D[i] / noise) }
        let separation = coreZ.isEmpty ? 0 : median(coreZ)
        notes["separation"] = Double(separation)
        guard separation >= 6 else { notes["colourEvidence"] = 0; return nil }
        notes["colourEvidence"] = 1

        var fgArea = fg.reduce(0) { $0 + ($1 ? 1 : 0) }
        var warning: String?

        // Recover parts the model missed: regions that are clearly not background, touch the
        // item, and are made of the same material as the part of the item they touch
        // (a strap continuing from a watch). Background texture, other objects and shadows fail
        // the material test and are left out.
        let reach = fgPlane.boxBlurred(radius: max(4, Int(0.10 * longSide)))
        var cand = [Bool](repeating: false, count: n)
        for i in 0..<n where !fg[i] && !shadowLike[i] && reach.data[i] > 0 && D[i] / noise > 12 { cand[i] = true }
        let (cl, cs) = Regions.label(cand, width: w, height: h)
        // Mean colour per candidate region, and the mean colour of the item pixels it touches.
        let nc = cs.count
        var sumC = [Float](repeating: 0, count: nc * 3), sumT = [Float](repeating: 0, count: nc * 3), cntT = [Int](repeating: 0, count: nc)
        for i in 0..<n {
            let l = Int(cl[i]); if l == 0 { continue }
            sumC[l * 3] += R.data[i]; sumC[l * 3 + 1] += G.data[i]; sumC[l * 3 + 2] += B.data[i]
            let x = i % w, y = i / w
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < w && ny < h {
                let j = ny * w + nx
                if fg[j] && p.data[j] > 0.8 {
                    sumT[l * 3] += R.data[j]; sumT[l * 3 + 1] += G.data[j]; sumT[l * 3 + 2] += B.data[j]; cntT[l] += 1
                }
            }
        }
        var accept = [Bool](repeating: false, count: nc)
        var recoveredCount = 0
        let maxRegion = max(20, Int(0.15 * Float(fgArea)))
        for l in 1..<nc where cntT[l] >= 3 && cs[l] <= maxRegion {
            let cr = sumC[l * 3] / Float(cs[l]), cg = sumC[l * 3 + 1] / Float(cs[l]), cb = sumC[l * 3 + 2] / Float(cs[l])
            let tr = sumT[l * 3] / Float(cntT[l]), tg = sumT[l * 3 + 1] / Float(cntT[l]), tb = sumT[l * 3 + 2] / Float(cntT[l])
            let d = sqrt((cr - tr) * (cr - tr) + (cg - tg) * (cg - tg) + (cb - tb) * (cb - tb))
            if d < 0.10 { accept[l] = true; recoveredCount += cs[l] }
        }
        notes["recoveredPx"] = Double(recoveredCount)
        if recoveredCount > 0 {
            for i in 0..<n where accept[Int(cl[i])] { fg[i] = true; p.data[i] = 1 }
            fgArea += recoveredCount
        }

        // Carve gaps the model filled in (between comb teeth, inside a handle): small regions
        // inside the item whose colour is indistinguishable from the background around it.
        // Large look-alike areas are part of the product (white on white) and are kept.
        var carved = 0
        if separation >= 10 {
            var hole = [Bool](repeating: false, count: n)
            for i in 0..<n where fg[i] && D[i] / noise < 1.5 { hole[i] = true }
            let (hl, hs) = Regions.label(hole, width: w, height: h)
            let minHole = max(12, Int(0.0002 * Float(n)))
            let maxHole = Int(0.05 * Float(fgArea))
            var carve = [Bool](repeating: false, count: hs.count)
            for c in 1..<hs.count where hs[c] >= minHole && hs[c] <= maxHole { carve[c] = true; carved += hs[c] }
            if Float(carved) > 0.12 * Float(fgArea) {
                warning = "Parts of the item look like the background"
                notes["carveRejected"] = 1
                carved = 0
            } else if carved > 0 {
                for i in 0..<n where hole[i] && carve[Int(hl[i])] { fg[i] = false; p.data[i] = 0 }
            }
        }
        notes["carvedPx"] = Double(carved)

        if recoveredCount > 0 || carved > 0 {
            // The edits are hard-edged at working resolution; soften by a pixel so the
            // guided filter can place the edge precisely.
            p = p.gaussianBlurred(sigma: 0.8)
        }
        return warning
    }

    // MARK: Guided upsampling

    /// Colour guided filter at working resolution; coefficients bilinearly upsampled and
    /// applied to every full-resolution pixel (He & Sun, "Fast Guided Filter").
    static func guidedUpsample(full: RGBAImage, R: Plane, G: Plane, B: Plane, p: Plane,
                               radius r: Int, eps: Float, low: Float, high: Float) -> [UInt8] {
        let w = p.width, h = p.height, n = w * h
        func mean(_ x: Plane) -> Plane { x.boxBlurred(radius: r) }
        let mR = mean(R), mG = mean(G), mB = mean(B), mP = mean(p)
        let mRP = mean(R * p), mGP = mean(G * p), mBP = mean(B * p)
        let mRR = mean(R * R), mRG = mean(R * G), mRB = mean(R * B)
        let mGG = mean(G * G), mGB = mean(G * B), mBB = mean(B * B)

        var aR = [Float](repeating: 0, count: n), aG = aR, aB = aR, bb = aR
        for i in 0..<n {
            let mr = mR.data[i], mg = mG.data[i], mb = mB.data[i], mp = mP.data[i]
            let cr = mRP.data[i] - mr * mp, cg = mGP.data[i] - mg * mp, cb = mBP.data[i] - mb * mp
            let s11 = mRR.data[i] - mr * mr + eps, s12 = mRG.data[i] - mr * mg, s13 = mRB.data[i] - mr * mb
            let s22 = mGG.data[i] - mg * mg + eps, s23 = mGB.data[i] - mg * mb, s33 = mBB.data[i] - mb * mb + eps
            // Inverse of the symmetric 3x3 covariance via cofactors.
            let c11 = s22 * s33 - s23 * s23, c12 = s13 * s23 - s12 * s33, c13 = s12 * s23 - s13 * s22
            let c22 = s11 * s33 - s13 * s13, c23 = s13 * s12 - s11 * s23, c33 = s11 * s22 - s12 * s12
            let det = s11 * c11 + s12 * c12 + s13 * c13
            if abs(det) < 1e-12 { bb[i] = mp; continue }
            let inv = 1 / det
            let ar = (c11 * cr + c12 * cg + c13 * cb) * inv
            let ag = (c12 * cr + c22 * cg + c23 * cb) * inv
            let ab = (c13 * cr + c23 * cg + c33 * cb) * inv
            aR[i] = ar; aG[i] = ag; aB[i] = ab
            bb[i] = mp - ar * mr - ag * mg - ab * mb
        }
        let maR = mean(Plane(width: w, height: h, data: aR))
        let maG = mean(Plane(width: w, height: h, data: aG))
        let maB = mean(Plane(width: w, height: h, data: aB))
        let mb = mean(Plane(width: w, height: h, data: bb))

        // Edge-band matting. Near the outline, estimate the item's colour (F) and the background's
        // colour (B) locally from confident pixels on each side, then solve each full-resolution
        // pixel's alpha as how far its colour lies from B towards F. This puts the edge where the
        // photo has it, keeps genuinely mixed pixels partial, and is trusted only where F and B
        // differ clearly; elsewhere the guided-filter result stands.
        let fW = p.map { $0 >= 0.97 ? 1 : 0 }, bW = p.map { $0 <= 0.03 ? 1 : 0 }
        // Local colour means at two reaches: near (preferred) and wide (when the model's edge is
        // so soft that no confident pixels are near).
        func means(_ rm: Int) -> [Plane] {
            let dF = fW.boxBlurred(radius: rm), dB = bW.boxBlurred(radius: rm)
            func localMean(_ c: Plane, _ wt: Plane, _ d: Plane) -> Plane {
                Plane.combine((c * wt).boxBlurred(radius: rm), d) { a, dd in dd > 0.01 ? a / dd : -1 }
            }
            return [localMean(R, fW, dF), localMean(G, fW, dF), localMean(B, fW, dF),
                    localMean(R, bW, dB), localMean(G, bW, dB), localMean(B, bW, dB)]
        }
        let near = means(max(4, r * 3)), wide = means(max(8, r * 8))
        let bandRaw = p.map { $0 > 0.03 && $0 < 0.97 ? 1 : 0 }.boxBlurred(radius: r)

        let fw = full.width, fh = full.height
        let sx = Float(w) / Float(fw), sy = Float(h) / Float(fh)
        let inv255: Float = 1.0 / 255.0
        let span = max(0.001, high - low)
        var out = [UInt8](repeating: 0, count: fw * fh)
        full.pixels.withUnsafeBufferPointer { px in
            out.withUnsafeMutableBufferPointer { o in
                for y in 0..<fh {
                    let fy = (Float(y) + 0.5) * sy
                    for x in 0..<fw {
                        let fx = (Float(x) + 0.5) * sx
                        let i = y * fw + x
                        let r0 = Float(px[i * 4]) * inv255, g0 = Float(px[i * 4 + 1]) * inv255, b0 = Float(px[i * 4 + 2]) * inv255
                        var q = maR.sample(fx, fy) * r0 + maG.sample(fx, fy) * g0 + maB.sample(fx, fy) * b0 + mb.sample(fx, fy)
                        if bandRaw.sample(fx, fy) > 0.001 {
                            var set = near
                            if near[0].sample(fx, fy) < 0 || near[3].sample(fx, fy) < 0 { set = wide }
                            let fr = set[0].sample(fx, fy), fgc = set[1].sample(fx, fy), fb = set[2].sample(fx, fy)
                            let br = set[3].sample(fx, fy), bg = set[4].sample(fx, fy), bbc = set[5].sample(fx, fy)
                            if fr >= 0 && br >= 0 {
                                let er = fr - br, eg = fgc - bg, eb = fb - bbc
                                let c2 = er * er + eg * eg + eb * eb
                                let c = sqrt(c2)
                                if c > 0.06 {
                                    var ap = ((r0 - br) * er + (g0 - bg) * eg + (b0 - bbc) * eb) / c2
                                    ap = ap < 0 ? 0 : (ap > 1 ? 1 : ap)
                                    let t = min(1, (c - 0.06) / 0.12)
                                    let trustContrast = t * t * (3 - 2 * t)
                                    let pc = p.sample(fx, fy)
                                    let m = 2 * pc - 1
                                    let trustBand = 1 - m * m
                                    let wgt = trustContrast * trustBand
                                    q = q * (1 - wgt) + ap * wgt
                                }
                            }
                        }
                        var a = (q - low) / span
                        a = a < 0 ? 0 : (a > 1 ? 1 : a)
                        o[i] = UInt8(a * 255 + 0.5)
                    }
                }
            }
        }
        return out
    }

    static func levels(_ p: Plane, low: Float, high: Float) -> [UInt8] {
        let span = max(0.001, high - low)
        return Plane(width: p.width, height: p.height, data: p.data.map { min(1, max(0, ($0 - low) / span)) }).toBytes()
    }

    static func median(_ v: [Float]) -> Float {
        guard !v.isEmpty else { return 0 }
        var s = v
        s.sort()
        return s[s.count / 2]
    }

    // MARK: Foreground colour estimation

    /// Removes the old background's colour from semi-transparent edge pixels.
    /// Approximate fast foreground colour estimation (Forte & Pitié, 2021): two passes of
    /// "blur fusion", a wide one at working resolution and a narrow one at full resolution.
    public static func foreground(full: RGBAImage, alpha: [UInt8]) -> RGBAImage {
        let fw = full.width, fh = full.height
        let longF = Float(max(fw, fh))
        // Coarse pass at working resolution.
        let k = min(1, 1024 / longF)
        let ww = max(1, Int(Float(fw) * k)), wh = max(1, Int(Float(fh) * k))
        let small = full.resized(width: ww, height: wh)
        let aSmall = Plane(bytes: alpha, width: fw, height: fh).resized(width: ww, height: wh)
        let I = [small.channel(0), small.channel(1), small.channel(2)]
        let r1 = max(2, Int(0.04 * Float(max(ww, wh))))
        let (F1, B1) = blurFusion(I: I, F: I, B: I, alpha: aSmall, radius: r1)

        // Fine pass at full resolution, in strips, only where the matte is partial.
        var out = full
        let r2 = max(2, Int(0.0025 * longF))
        let strip = 192
        let margin = r2 + 1
        let sx = Float(ww) / Float(fw), sy = Float(wh) / Float(fh)
        var y0 = 0
        while y0 < fh {
            let y1 = min(fh, y0 + strip)
            // Skip strips with no partial alpha.
            var partial = false
            for i in (y0 * fw)..<(y1 * fw) where alpha[i] > 0 && alpha[i] < 255 { partial = true; break }
            if !partial { y0 = y1; continue }
            let ys = max(0, y0 - margin), ye = min(fh, y1 + margin), sh = ye - ys
            let m = fw * sh
            var a = [Float](repeating: 0, count: m)
            var Ic = [[Float]](repeating: [Float](repeating: 0, count: m), count: 3)
            var Fc = Ic, Bc = Ic
            for yy in 0..<sh {
                let y = ys + yy
                let fy = (Float(y) + 0.5) * sy
                for x in 0..<fw {
                    let i = y * fw + x, j = yy * fw + x
                    a[j] = Float(alpha[i]) / 255
                    let fx = (Float(x) + 0.5) * sx
                    for c in 0..<3 {
                        Ic[c][j] = Float(full.pixels[i * 4 + c]) / 255
                        Fc[c][j] = F1[c].sample(fx, fy)
                        Bc[c][j] = B1[c].sample(fx, fy)
                    }
                }
            }
            let aP = Plane(width: fw, height: sh, data: a)
            let (F2, _) = blurFusion(I: Ic.map { Plane(width: fw, height: sh, data: $0) },
                                     F: Fc.map { Plane(width: fw, height: sh, data: $0) },
                                     B: Bc.map { Plane(width: fw, height: sh, data: $0) },
                                     alpha: aP, radius: r2)
            for y in y0..<y1 {
                let yy = y - ys
                for x in 0..<fw {
                    let i = y * fw + x
                    let av = alpha[i]
                    if av == 0 || av == 255 { continue }
                    let j = yy * fw + x
                    for c in 0..<3 {
                        let v = F2[c].data[j] * 255 + 0.5
                        out.pixels[i * 4 + c] = v <= 0 ? 0 : (v >= 255 ? 255 : UInt8(v))
                    }
                }
            }
            y0 = y1
        }
        return out
    }

    private static func blurFusion(I: [Plane], F: [Plane], B: [Plane], alpha: Plane, radius r: Int) -> ([Plane], [Plane]) {
        let n = alpha.count
        let blurA = alpha.boxBlurred(radius: r)
        let inv = alpha.map { 1 - $0 }
        let blurInv = inv.boxBlurred(radius: r)
        var Fo: [Plane] = [], Bo: [Plane] = []
        for c in 0..<3 {
            let Fb = Plane.combine((F[c] * alpha).boxBlurred(radius: r), blurA) { x, d in d > 1e-5 ? x / d : 0 }
            let Bb = Plane.combine((B[c] * inv).boxBlurred(radius: r), blurInv) { x, d in d > 1e-5 ? x / d : 0 }
            var f = [Float](repeating: 0, count: n)
            for i in 0..<n {
                let a = alpha.data[i]
                let v = Fb.data[i] + a * (I[c].data[i] - a * Fb.data[i] - (1 - a) * Bb.data[i])
                f[i] = v < 0 ? 0 : (v > 1 ? 1 : v)
            }
            Fo.append(Plane(width: alpha.width, height: alpha.height, data: f))
            Bo.append(Bb)
        }
        return (Fo, Bo)
    }
}

/// Connected regions (4-connected) of a boolean mask. Label 0 is "not in mask".
enum Regions {
    static func label(_ mask: [Bool], width w: Int, height h: Int) -> (labels: [Int32], sizes: [Int]) {
        var labels = [Int32](repeating: 0, count: w * h)
        var sizes: [Int] = [0]
        var stack: [Int32] = []
        stack.reserveCapacity(4096)
        var next: Int32 = 1
        for start in 0..<(w * h) where mask[start] && labels[start] == 0 {
            labels[start] = next
            stack.append(Int32(start))
            var size = 0
            while let t = stack.popLast() {
                let i = Int(t)
                size += 1
                let x = i % w, y = i / w
                if x > 0, mask[i - 1], labels[i - 1] == 0 { labels[i - 1] = next; stack.append(Int32(i - 1)) }
                if x < w - 1, mask[i + 1], labels[i + 1] == 0 { labels[i + 1] = next; stack.append(Int32(i + 1)) }
                if y > 0, mask[i - w], labels[i - w] == 0 { labels[i - w] = next; stack.append(Int32(i - w)) }
                if y < h - 1, mask[i + w], labels[i + w] == 0 { labels[i + w] = next; stack.append(Int32(i + w)) }
            }
            sizes.append(size)
            next += 1
        }
        return (labels, sizes)
    }
}
