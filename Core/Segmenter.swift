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
    /// What the network passes decided, for the test bench (doubtful, grey canvas verdict, ...).
    public var notes: [String: Double] = [:]
}

public enum Segmenter {
    public static let workLongSide = 1536
    /// A first result running off more than this share of the frame's border is doubtful (was 3%;
    /// the Columbia side close-up's ruler touched 3.4%, too near the line).
    static let doubtfulBorderShare: Float = 0.02
    /// The first pass is also doubtful when it and Apple's subject finder overlap less than this.
    static let appleDisagreement: Float = 0.8
    /// The detail crop runs only when it covers less than this share of the photo.
    public static let zoomMaxShare: CGFloat = 0.5

    /// What surrounds the photo when the network is shown it on a larger canvas.
    enum Canvas { case mirrored, grey }
    enum CanvasVerdict { case accept, agree, reject }

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

    /// A rough cutout from Apple's subject finder alone, at the image's own size, in a fraction
    /// of a second. Shown while the full cutout is made. nil when it sees no item.
    public static func quickMask(_ image: CGImage) -> Plane? {
        (try? mask(of: image, network: nil))?.prob
    }

    // MARK: Cutout network

    /// The cutout network, in up to three passes.
    ///
    /// 1. The whole photo, as is. Right for nearly every shot of a whole item.
    /// 2. Only when that result looks doubtful (it runs off the frame, it is small, or Apple's
    ///    subject finder sees a quite different item): the photo on a flat grey canvas, then if
    ///    that is turned down, on its own mirrored edges. On a close-up where the garment fills the frame, a cutout
    ///    network picks the most distinct thing inside it (a tape measure, a label); with room
    ///    around it, the garment is the object. The canvas version is accepted only when what it
    ///    adds looks clearly unlike the background that remains, because on a plain backdrop the
    ///    backdrop itself can become "an object" against the canvas.
    /// 3. A tighter crop around the item, so the network spends its 1024 pixels on the item's
    ///    edges, only when the crop is under half the photo. Used where it agrees so far.
    static func networkSegment(_ full: CGImage, ww: Int, wh: Int, zoom: Bool, network: CutoutNetwork) throws -> Segmentation? {
        let fw = CGFloat(full.width), fh = CGFloat(full.height)
        let whole = CGRect(x: 0, y: 0, width: fw, height: fh)
        // Apple's subject finder first, while the network is unloaded (the two together don't fit
        // in an iPhone 11): its view is the second opinion for parts the network drops (below),
        // and a strong disagreement with the network's first pass marks the photo as doubtful.
        // Skipped, rather than risk the app being closed, if memory is short anyway.
        network.unload()
        var small: RGBAImage? = nil
        var vision: Plane? = nil
        if Diagnostics.canSpare(450), let s = RGBAImage(cgImage: full, width: ww, height: wh) {
            small = s
            if let cg = s.makeOpaqueCGImage(), let v = try? mask(of: cg, network: nil) { vision = v.prob }
        }
        Diagnostics.note(vision == nil ? "second opinion skipped" : "second opinion ready")
        Diagnostics.note("network starts")
        // Never leave the network loaded, even when this photo gives up early: the next photo's
        // quick cutout runs Apple's model, and the two together don't fit in an iPhone 11.
        defer { network.unload() }
        guard var prob = try pass(full, region: whole, pads: (0, 0, 0, 0), outW: ww, outH: wh, network: network) else { return nil }
        var canvasUsed = false
        var canvasKind = Canvas.mirrored
        // A close-up whose ruler barely touches the frame isn't caught by the border test (the
        // Columbia side close-up, quality run 58); Apple's model then sees far more item.
        let agreement = vision.map { overlap($0, prob) } ?? 1
        let isDoubtful = doubtful(prob) || agreement < appleDisagreement
        var notes: [String: Double] = ["doubtful": isDoubtful ? 1 : 0, "greyCanvas": -1, "mirroredCanvas": 0,
                                       "appleAgreement": vision == nil ? -1 : Double(agreement)]
        if small == nil, isDoubtful { small = RGBAImage(cgImage: full, width: ww, height: wh) }
        if isDoubtful, let small {
            let m = 0.35 * max(fw, fh)
            // Close-ups first: the photo on a flat grey canvas, so a garment that fills the frame
            // becomes an object with an outline instead of "the background" (the network then
            // picks whatever sits on top of it, such as a ruler or a sleeve). Kept only when what
            // it adds doesn't look like the surface that remains and it isn't the whole frame.
            var verdict = CanvasVerdict.reject
            if let grey = try pass(full, region: whole, pads: (m, m, m, m), outW: ww, outH: wh, network: network, canvas: .grey) {
                verdict = acceptCanvas(plain: prob, wide: grey, image: small)
                if verdict == .accept { prob = grey; canvasUsed = true; canvasKind = .grey }
                notes["greyCanvas"] = verdict == .accept ? 1 : (verdict == .agree ? 0 : 2)
                Diagnostics.note("grey canvas \(verdict)")
            }
            // The grey canvas can make a plain surface read as an object (the whole rectangle).
            // Then the photo's own mirrored edges are tried, as before.
            if verdict == .reject,
               let wide = try pass(full, region: whole, pads: (m, m, m, m), outW: ww, outH: wh, network: network),
               preferWide(plain: prob, wide: wide, image: small) {
                prob = wide
                canvasUsed = true
                notes["mirroredCanvas"] = 1
            }
        }
        guard prob.data.contains(where: { $0 > 0.5 }) else { return nil }
        var zoomed = false
        if zoom, let box = bbox(prob, threshold: 0.5) {
            let s = fw / CGFloat(ww)
            let margin = 0.08 * CGFloat(max(box.width, box.height)) * s
            let r = CGRect(x: CGFloat(box.minX) * s - margin, y: CGFloat(box.minY) * s - margin,
                           width: CGFloat(box.width) * s + 2 * margin, height: CGFloat(box.height) * s + 2 * margin).intersection(whole).integral.intersection(whole)
            // Only worth it when the crop is much smaller than the photo: on Woolfall's real photos
            // (garments filling 30 to 45% of the frame) the crop gave no better edges than the
            // whole photo, after the full-size edge refinement, but cost a whole network run.
            if r.width * r.height < zoomMaxShare * fw * fh {
                // Canvas only on sides where the item runs off the frame, and only if the canvas
                // was needed for the whole photo too.
                let pad = canvasUsed ? 0.12 * max(r.width, r.height) : 0
                let touch = (l: r.minX <= 1, t: r.minY <= 1, r: r.maxX >= fw - 1, b: r.maxY >= fh - 1)
                let pads = (touch.l ? pad : 0, touch.t ? pad : 0, touch.r ? pad : 0, touch.b ? pad : 0)
                let rx = Int((r.minX / s).rounded()), ry = Int((r.minY / s).rounded())
                let rw = max(1, min(ww - rx, Int((r.width / s).rounded()))), rh = max(1, min(wh - ry, Int((r.height / s).rounded())))
                if let detail = try pass(full, region: r, pads: pads, outW: rw, outH: rh, network: network, canvas: canvasKind) {
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
        Diagnostics.note("network done")
        // The network keeps a lot of working memory after a prediction. Let it go before Apple's
        // model loads: the two together went over an iPhone 11's memory limit.
        network.unload()
        Diagnostics.note("network unloaded")
        // The second opinion, for parts the network dropped.
        if let vision, let small {
            _ = recoverParts(&prob, vision: vision, image: small)
            Diagnostics.note("second opinion done")
        }
        return Segmentation(prob: prob, instanceCount: 1, zoomed: zoomed, notes: notes)
    }

    /// Adds back parts Apple's subject finder includes but the network left out: a cuff, the end
    /// of a strap, a pale lining. Apple's model judges whole objects; the network draws crisper
    /// outlines but now and then drops a part that looks unlike the rest of the item.
    ///
    /// Each disputed piece must touch the item, be smaller than it, and mostly not look like the
    /// surface around it: its colours are compared with the surface and the item nearby, and
    /// anything that reads as the surface in shadow (same colour, only darker) counts as surface.
    /// Returns how many pixels were added.
    static func recoverParts(_ prob: inout Plane, vision: Plane, image: RGBAImage) -> Int {
        let w = prob.width, h = prob.height, n = w * h
        guard vision.width == w, vision.height == h, image.width == w, image.height == h, n > 0 else { return 0 }
        var fg = [Bool](repeating: false, count: n), disputed = [Bool](repeating: false, count: n)
        var fgCount = 0
        for i in 0..<n {
            fg[i] = prob.data[i] > 0.5
            if fg[i] { fgCount += 1 }
            disputed[i] = !fg[i] && vision.data[i] > 0.6
        }
        guard fgCount > 0 else { return 0 }
        let (labels, sizes) = Regions.label(disputed, width: w, height: h)
        let count = sizes.count
        guard count > 1 else { return 0 }
        var minX = [Int](repeating: w, count: count), minY = [Int](repeating: h, count: count)
        var maxX = [Int](repeating: -1, count: count), maxY = [Int](repeating: -1, count: count)
        var touches = [Bool](repeating: false, count: count)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x, c = Int(labels[i])
                if c == 0 { continue }
                minX[c] = min(minX[c], x); maxX[c] = max(maxX[c], x)
                minY[c] = min(minY[c], y); maxY[c] = max(maxY[c], y)
                if !touches[c] {
                    if (x > 0 && fg[i - 1]) || (x < w - 1 && fg[i + 1]) || (y > 0 && fg[i - w]) || (y < h - 1 && fg[i + w]) {
                        touches[c] = true
                    }
                }
            }
        }
        let px = image.pixels
        @inline(__always) func bin(_ i: Int) -> Int {
            let p = i * 4
            return (Int(px[p]) >> 4) << 8 | (Int(px[p + 1]) >> 4) << 4 | Int(px[p + 2]) >> 4
        }
        /// Density of a colour bin, smoothed over its neighbouring bins.
        func density(_ hist: [Int], _ total: Int, _ b: Int) -> Float {
            guard total > 0 else { return 0 }
            let r = b >> 8, g = (b >> 4) & 15, bl = b & 15
            var sum = 0
            for dr in -1...1 { let rr = r + dr; if rr < 0 || rr > 15 { continue }
                for dg in -1...1 { let gg = g + dg; if gg < 0 || gg > 15 { continue }
                    for db in -1...1 { let bb = bl + db; if bb < 0 || bb > 15 { continue }
                        sum += hist[rr << 8 | gg << 4 | bb]
                    }
                }
            }
            return Float(sum) / Float(total * 27)
        }
        let minSize = max(30, n / 4000)
        var added = 0
        for c in 1..<count where sizes[c] >= minSize && touches[c] && sizes[c] * 2 < fgCount {
            // The neighbourhood that describes this piece's surroundings.
            let bw = maxX[c] - minX[c] + 1, bh = maxY[c] - minY[c] + 1
            let m = Int(0.75 * Double(max(bw, bh))) + 8
            let x0 = max(0, minX[c] - m), x1 = min(w - 1, maxX[c] + m)
            let y0 = max(0, minY[c] - m), y1 = min(h - 1, maxY[c] + m)
            var bgHist = [Int](repeating: 0, count: 4096), fgHist = [Int](repeating: 0, count: 4096)
            var bgN = 0, fgN = 0
            var mean: (Float, Float, Float) = (0, 0, 0)
            for y in y0...y1 {
                for x in x0...x1 {
                    let i = y * w + x
                    if !fg[i] && vision.data[i] < 0.3 {
                        bgHist[bin(i)] += 1; bgN += 1
                        mean.0 += Float(px[i * 4]); mean.1 += Float(px[i * 4 + 1]); mean.2 += Float(px[i * 4 + 2])
                    } else if prob.data[i] > 0.8 {
                        fgHist[bin(i)] += 1; fgN += 1
                    }
                }
            }
            // Without a view of the surface there is nothing to judge against: leave it.
            guard bgN > 50 else { continue }
            mean = (max(1, mean.0 / Float(bgN)), max(1, mean.1 / Float(bgN)), max(1, mean.2 / Float(bgN)))
            var keep = [Int]()
            keep.reserveCapacity(sizes[c])
            var total = 0
            for y in minY[c]...maxY[c] {
                for x in minX[c]...maxX[c] {
                    let i = y * w + x
                    guard Int(labels[i]) == c else { continue }
                    total += 1
                    let b = bin(i)
                    let dB = density(bgHist, bgN, b), dF = density(fgHist, fgN, b)
                    var surface = dB > 3 * dF && dB > 2 / 4096
                    if !surface {
                        // The surface in shadow: each channel dimmed by about the same amount.
                        let r = Float(px[i * 4]) / mean.0, g = Float(px[i * 4 + 1]) / mean.1, bl = Float(px[i * 4 + 2]) / mean.2
                        let lo = min(r, g, bl), hi = max(r, g, bl)
                        if lo > 0.2 && hi < 0.97 && hi - lo < 0.12 { surface = true }
                    }
                    if !surface { keep.append(i) }
                }
            }
            guard total > 0, Float(keep.count) >= 0.6 * Float(total) else { continue }
            for i in keep where vision.data[i] > prob.data[i] {
                prob.data[i] = vision.data[i]
                added += 1
            }
        }
        return added
    }

    /// A first result is doubtful when it runs off the frame (more than 3% of the border) or is small.
    static func doubtful(_ p: Plane) -> Bool {
        let w = p.width, h = p.height
        var on = 0, total = 0
        for x in 0..<w { on += (p.data[x] > 0.5 ? 1 : 0) + (p.data[(h - 1) * w + x] > 0.5 ? 1 : 0); total += 2 }
        for y in 0..<h { on += (p.data[y * w] > 0.5 ? 1 : 0) + (p.data[y * w + w - 1] > 0.5 ? 1 : 0); total += 2 }
        let area = Float(p.data.filter { $0 > 0.5 }.count) / Float(p.count)
        return Float(on) / Float(total) > doubtfulBorderShare || area < 0.15
    }

    /// Whether the grey-canvas result should replace the plain one. `agree` when they barely
    /// differ (nothing to gain, and no need to try the mirrored canvas either). `reject` when it
    /// takes in nearly the whole frame (the rectangle), adds almost nothing, or what it adds looks
    /// like the surface that remains. Colours are compared as distributions (16-level colour
    /// histograms, smoothed), not as averages: a navy and cream striped body averages out to a
    /// grey much like concrete, but none of its colours is concrete's. An added pixel counts as
    /// surface when its colour is at least half as common in the remaining surface as in the
    /// added region itself: a slab of wood above a pair of sunglasses matches the wood left below
    /// them; a garment doesn't match the concrete around it (checked on Woolfall's close-ups and
    /// on slabs of floor added to the normal photos, tools/netlab/guard_v2.py).
    static func acceptCanvas(plain: Plane, wide: Plane, image: RGBAImage) -> CanvasVerdict {
        let n = plain.count
        guard wide.count == n, image.width * image.height == n, n > 0 else { return .reject }
        var inter = 0, uni = 0, added = 0, rest = 0, item = 0
        for i in 0..<n {
            let a = plain.data[i] > 0.5, b = wide.data[i] > 0.5
            if a && b { inter += 1 }
            if a || b { uni += 1 }
            if b { item += 1 }
            if b && !a { added += 1 }
            if !a && !b { rest += 1 }
        }
        if Float(item) >= 0.97 * Float(n) { return .reject }
        if uni > 0 && Float(inter) / Float(uni) >= 0.9 { return .agree }
        if Float(added) < 0.01 * Float(n) { return .reject }
        if Float(rest) < 0.02 * Float(n) { return .accept }
        let px = image.pixels
        var bins = [Int](repeating: 0, count: n)
        var restHist = [Int](repeating: 0, count: 4096), addedHist = [Int](repeating: 0, count: 4096)
        for i in 0..<n {
            let p = i * 4
            let b = (Int(px[p]) >> 4) << 8 | (Int(px[p + 1]) >> 4) << 4 | Int(px[p + 2]) >> 4
            bins[i] = b
            let a = plain.data[i] > 0.5, w = wide.data[i] > 0.5
            if w && !a { addedHist[b] += 1 } else if !a && !w { restHist[b] += 1 }
        }
        var surfaceLike = 0
        for i in 0..<n where wide.data[i] > 0.5 && plain.data[i] <= 0.5 {
            let dB = binDensity(restHist, rest, bins[i]), dA = binDensity(addedHist, added, bins[i])
            if dB > 0.5 * dA && dB > 2 / 4096 { surfaceLike += 1 }
        }
        return Float(surfaceLike) < 0.4 * Float(added) ? .accept : .reject
    }

    /// Intersection over union of two maps' item areas (above 0.5).
    static func overlap(_ a: Plane, _ b: Plane) -> Float {
        guard a.count == b.count, a.count > 0 else { return 0 }
        var inter = 0, uni = 0
        for i in 0..<a.count {
            let x = a.data[i] > 0.5, y = b.data[i] > 0.5
            if x && y { inter += 1 }
            if x || y { uni += 1 }
        }
        return uni == 0 ? 1 : Float(inter) / Float(uni)
    }

    /// Share of a histogram's pixels in a colour bin and its 26 neighbours, per bin.
    static func binDensity(_ hist: [Int], _ total: Int, _ b: Int) -> Float {
        guard total > 0 else { return 0 }
        let r = b >> 8, g = (b >> 4) & 15, bl = b & 15
        var sum = 0
        for dr in -1...1 { let rr = r + dr; if rr < 0 || rr > 15 { continue }
            for dg in -1...1 { let gg = g + dg; if gg < 0 || gg > 15 { continue }
                for db in -1...1 { let bb = bl + db; if bb < 0 || bb > 15 { continue }
                    sum += hist[rr << 8 | gg << 4 | bb]
                }
            }
        }
        return Float(sum) / Float(total * 27)
    }

    /// Whether the canvas result should replace the plain one: they disagree, and what the canvas
    /// version adds looks clearly unlike the background that remains (or nearly nothing remains).
    static func preferWide(plain: Plane, wide: Plane, image: RGBAImage) -> Bool {
        let n = plain.count
        var inter = 0, uni = 0, added = 0, rest = 0
        for i in 0..<n {
            let a = plain.data[i] > 0.5, b = wide.data[i] > 0.5
            if a && b { inter += 1 }
            if a || b { uni += 1 }
            if b && !a { added += 1 }
            if !a && !b { rest += 1 }
        }
        if uni > 0 && Float(inter) / Float(uni) >= 0.9 { return false }
        if Float(added) < 0.01 * Float(n) { return false }
        if Float(rest) < 0.02 * Float(n) { return true }
        var ma: (Float, Float, Float) = (0, 0, 0), mr: (Float, Float, Float) = (0, 0, 0)
        var labs = [(Float, Float, Float)](repeating: (0, 0, 0), count: n)
        for i in 0..<n {
            let l = lab(image.pixels[i * 4], image.pixels[i * 4 + 1], image.pixels[i * 4 + 2])
            labs[i] = l
            let a = plain.data[i] > 0.5, b = wide.data[i] > 0.5
            if b && !a { ma.0 += l.0; ma.1 += l.1; ma.2 += l.2 }
            if !a && !b { mr.0 += l.0; mr.1 += l.1; mr.2 += l.2 }
        }
        let fa = Float(added), fr = Float(rest)
        ma = (ma.0 / fa, ma.1 / fa, ma.2 / fa); mr = (mr.0 / fr, mr.1 / fr, mr.2 / fr)
        var sp: (Float, Float, Float) = (0, 0, 0)
        for i in 0..<n where plain.data[i] <= 0.5 && wide.data[i] <= 0.5 {
            sp.0 += abs(labs[i].0 - mr.0); sp.1 += abs(labs[i].1 - mr.1); sp.2 += abs(labs[i].2 - mr.2)
        }
        sp = (sp.0 / fr, sp.1 / fr, sp.2 / fr)
        let d = sqrt((ma.0 - mr.0) * (ma.0 - mr.0) + (ma.1 - mr.1) * (ma.1 - mr.1) + (ma.2 - mr.2) * (ma.2 - mr.2))
        let spread = sqrt(sp.0 * sp.0 + sp.1 * sp.1 + sp.2 * sp.2)
        return d > 12 && d > 1.5 * spread
    }

    /// CIE Lab (D65) from 8-bit sRGB.
    static func lab(_ r8: UInt8, _ g8: UInt8, _ b8: UInt8) -> (Float, Float, Float) {
        func lin(_ v: UInt8) -> Float { let c = Float(v) / 255; return c > 0.04045 ? powf((c + 0.055) / 1.055, 2.4) : c / 12.92 }
        let r = lin(r8), g = lin(g8), b = lin(b8)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.9505
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.089
        func f(_ t: Float) -> Float { t > 0.008856 ? cbrtf(t) : 7.787 * t + 16 / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// Runs the network on a region of the photo extended by the given padding (left, top, right,
    /// bottom, in photo pixels). Mirrored: the padding continues the photo's own edges, mirrored
    /// and blurred, so there is no frame for the network to pick out. Grey: a flat grey canvas,
    /// which makes a frame-filling close-up read as an object, but can make a small item on a
    /// plain surface read as "a rectangle" (so its result is checked by `acceptCanvas`).
    /// Returns the region's probability at outW x outH.
    private static func pass(_ full: CGImage, region: CGRect, pads: (CGFloat, CGFloat, CGFloat, CGFloat),
                             outW: Int, outH: Int, network: CutoutNetwork, canvas kind: Canvas = .mirrored) throws -> Plane? {
        let side = CutoutNetwork.side
        let cw = region.width + pads.0 + pads.2, ch = region.height + pads.1 + pads.3
        let sx = CGFloat(side) / cw, sy = CGFloat(side) / ch
        let whole = CGRect(x: 0, y: 0, width: full.width, height: full.height)
        guard let crop = region == whole ? full : full.cropping(to: region) else { return nil }
        let ox = Int((pads.0 * sx).rounded()), oy = Int((pads.1 * sy).rounded())
        let iw = max(1, min(side - ox, Int((region.width * sx).rounded()))), ih = max(1, min(side - oy, Int((region.height * sy).rounded())))
        guard let img = RGBAImage(cgImage: crop, width: iw, height: ih) else { return nil }
        let n = side * side
        let padded = ox > 0 || oy > 0 || iw < side || ih < side
        var canvas = RGBAImage(width: side, height: side, fill: (128, 128, 128))
        if padded && kind == .mirrored {
            @inline(__always) func reflect(_ u: Int, _ len: Int) -> Int {
                if len == 1 { return 0 }
                let period = 2 * len
                var m = u % period
                if m < 0 { m += period }
                return m < len ? m : period - 1 - m
            }
            var planes = [[Float]](repeating: [Float](repeating: 0, count: n), count: 3)
            for y in 0..<side {
                let v = reflect(y - oy, ih)
                for x in 0..<side {
                    let u = reflect(x - ox, iw)
                    let si = (v * iw + u) * 4
                    for c in 0..<3 { planes[c][y * side + x] = Float(img.pixels[si + c]) }
                }
            }
            let sigma = Float(0.02 * max(region.width * sx, region.height * sy))
            for c in 0..<3 {
                let blurred = Plane(width: side, height: side, data: planes[c]).gaussianBlurred(sigma: max(1, sigma))
                for i in 0..<n { canvas.pixels[i * 4 + c] = UInt8(max(0, min(255, blurred.data[i] + 0.5))) }
            }
        }
        // The photo itself, sharp, in the middle.
        for y in 0..<ih {
            let row = (oy + y) * side + ox
            for x in 0..<iw {
                let d = (row + x) * 4, si = (y * iw + x) * 4
                canvas.pixels[d] = img.pixels[si]; canvas.pixels[d + 1] = img.pixels[si + 1]; canvas.pixels[d + 2] = img.pixels[si + 2]
                canvas.pixels[d + 3] = 255
            }
        }
        guard let cg = canvas.makeOpaqueCGImage(), let p = try network.probability(of: cg) else { return nil }
        let x0 = Float(ox), y0 = Float(oy), w = Float(iw), h = Float(ih)
        var out = [Float](repeating: 0, count: outW * outH)
        for y in 0..<outH {
            let fy = y0 + (Float(y) + 0.5) / Float(outH) * h
            for x in 0..<outW {
                out[y * outW + x] = p.sample(x0 + (Float(x) + 0.5) / Float(outW) * w, fy)
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
