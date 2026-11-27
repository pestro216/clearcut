import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ClearcutCore

final class CoreTests: XCTestCase {

    // MARK: Helpers

    func stepImage(w: Int, h: Int, edgeX: Int, left: (UInt8, UInt8, UInt8), right: (UInt8, UInt8, UInt8)) -> RGBAImage {
        var img = RGBAImage(width: w, height: h, fill: right)
        for y in 0..<h { for x in 0..<edgeX { let i = (y * w + x) * 4; img.pixels[i] = left.0; img.pixels[i + 1] = left.1; img.pixels[i + 2] = left.2 } }
        return img
    }

    // MARK: Orientation and size

    func testOrientationIsAppliedAndSizeKept() throws {
        // A 300 x 200 JPEG tagged "rotate 90" must decode as 200 x 300.
        let img = RGBAImage(width: 300, height: 200, fill: (200, 100, 50))
        let cg = try XCTUnwrap(img.makeOpaqueCGImage())
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let size = try XCTUnwrap(ImageIOHelpers.orientedSize(data as Data))
        XCTAssertEqual(size, CGSize(width: 200, height: 300))
        let loaded = try XCTUnwrap(ImageIOHelpers.loadOriented(data as Data))
        XCTAssertEqual(loaded.width, 200)
        XCTAssertEqual(loaded.height, 300)
    }

    func testCompositeKeepsPhotoSize() {
        let photo = RGBAImage(width: 321, height: 207, fill: (90, 90, 90))
        var alpha = [UInt8](repeating: 0, count: 321 * 207)
        for y in 50..<150 { for x in 100..<220 { alpha[y * 321 + x] = 255 } }
        let out = Compositor.render(photo: photo, alpha: alpha, backdrop: .colour(r: 1, g: 1, b: 1, studioLight: true), shadow: ShadowParams())
        XCTAssertEqual(out.width, 321)
        XCTAssertEqual(out.height, 207)
        XCTAssertEqual(out.pixels.count, 321 * 207 * 4)
    }

    func testTransparentExportCarriesAlpha() {
        let photo = RGBAImage(width: 40, height: 30, fill: (10, 20, 30))
        var alpha = [UInt8](repeating: 0, count: 40 * 30)
        alpha[15 * 40 + 20] = 255
        alpha[15 * 40 + 21] = 128
        let out = Compositor.render(photo: photo, alpha: alpha, backdrop: .transparent, shadow: ShadowParams())
        XCTAssertEqual(out.pixels[(15 * 40 + 20) * 4 + 3], 255)
        XCTAssertEqual(out.pixels[(15 * 40 + 21) * 4 + 3], 128)
        XCTAssertEqual(out.pixels[3], 0)
    }

    // MARK: Matting

    func testGuidedRefinementSnapsToTheRealEdge() {
        // Real edge at x = 400 in a 800 x 200 photo. The coarse probability is soft and 6 px off.
        let full = stepImage(w: 800, h: 200, edgeX: 400, left: (30, 30, 160), right: (230, 220, 200))
        let ww = 400, wh = 100
        var prob = Plane(width: ww, height: wh, value: 0)
        for y in 0..<wh { for x in 0..<ww {
            let t = (Float(x) - 203) / 4
            prob.data[y * ww + x] = 1 / (1 + exp(t))
        } }
        let seg = Segmentation(prob: prob, instanceCount: 1, zoomed: false)
        var opts = MatteOptions(); opts.colourEvidence = false
        let m = Matting.refine(full: full, segmentation: seg, options: opts)
        let row = 100 * 800
        // Left of the edge is item, right is background, within one pixel.
        XCTAssertGreaterThan(m.alpha[row + 397], 240)
        XCTAssertLessThan(m.alpha[row + 402], 15)
    }

    func testNoArtificialSteepeningOfGenuineSoftEdges() {
        // A genuinely soft edge (12 px ramp in the photo) should stay soft, not be forced hard.
        var full = RGBAImage(width: 600, height: 60, fill: (230, 230, 230))
        for y in 0..<60 { for x in 0..<600 {
            let t = min(1, max(0, (Float(x) - 294) / 12))
            let v = UInt8(40 * (1 - t) + 230 * t)
            let i = (y * 600 + x) * 4; full.pixels[i] = v; full.pixels[i + 1] = v; full.pixels[i + 2] = v
        } }
        var prob = Plane(width: 300, height: 30, value: 0)
        for y in 0..<30 { for x in 0..<300 { prob.data[y * 300 + x] = 1 / (1 + exp((Float(x) - 150) / 3)) } }
        var opts = MatteOptions(); opts.colourEvidence = false
        let m = Matting.refine(full: full, segmentation: Segmentation(prob: prob, instanceCount: 1, zoomed: false), options: opts)
        let row = 30 * 600
        let partial = (290..<312).filter { m.alpha[row + $0] > 20 && m.alpha[row + $0] < 235 }.count
        XCTAssertGreaterThanOrEqual(partial, 5, "soft edge was hardened")
    }

    func testForegroundEstimationRemovesBackgroundTint() {
        // Red item on green: edge pixels mix red and green. The estimated foreground should be red.
        let w = 200, h = 40
        var photo = RGBAImage(width: w, height: h, fill: (20, 200, 40))
        var alpha = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            let a = min(1, max(0, Float(100 - x) / 6 + 0.5))
            alpha[y * w + x] = UInt8(a * 255)
            let i = (y * w + x) * 4
            photo.pixels[i] = UInt8(220 * a + 20 * (1 - a)); photo.pixels[i + 1] = UInt8(30 * a + 200 * (1 - a)); photo.pixels[i + 2] = UInt8(30 * a + 40 * (1 - a))
        } }
        let fg = Matting.foreground(full: photo, alpha: alpha)
        let i = (20 * w + 100) * 4   // a half-transparent edge pixel
        XCTAssertGreaterThan(Int(fg.pixels[i]), 150, "red should be restored")
        XCTAssertLessThan(Int(fg.pixels[i + 1]), 110, "green spill should be removed")
    }

    func testIslandsAreRemoved() {
        let full = RGBAImage(width: 400, height: 300, fill: (200, 200, 200))
        var prob = Plane(width: 400, height: 300, value: 0)
        for y in 100..<200 { for x in 100..<250 { prob.data[y * 400 + x] = 1 } }
        for y in 20..<24 { for x in 350..<354 { prob.data[y * 400 + x] = 1 } }   // speck
        var opts = MatteOptions(); opts.colourEvidence = false; opts.guidedRefinement = false
        let m = Matting.refine(full: full, segmentation: Segmentation(prob: prob, instanceCount: 1, zoomed: false), options: opts)
        XCTAssertEqual(m.alpha[22 * 400 + 352], 0)
        XCTAssertEqual(m.alpha[150 * 400 + 150], 255)
    }

    func testEmptyMaskFailsLoudly() {
        let full = RGBAImage(width: 100, height: 100, fill: (200, 200, 200))
        let m = Matting.refine(full: full, segmentation: Segmentation(prob: Plane(width: 100, height: 100), instanceCount: 0, zoomed: false))
        if case .failed = m.confidence {} else { XCTFail("expected failure") }
    }

    // MARK: Shadows

    func testShadowFallsOutsideTheItemAndScalesWithThickness() throws {
        let w = 600, h = 400
        func reach(_ boxW: Int) throws -> Int {
            var alpha = [UInt8](repeating: 0, count: w * h)
            for y in (200 - boxW / 2)..<(200 + boxW / 2) { for x in 250..<350 { alpha[y * w + x] = 255 } }
            let s = try XCTUnwrap(ShadowModel.density(alpha: alpha, width: w, height: h, params: ShadowParams(kind: .flatlay, strength: 0.6, angle: 90)))
            // Distance below the item at which the shadow drops under 2%.
            var y = 200 + boxW / 2
            while y < h - 1 && s[y * w + 300] > 5 { y += 1 }
            return y - (200 + boxW / 2)
        }
        let thin = try reach(10), thick = try reach(160)
        XCTAssertGreaterThan(thin, 0)
        XCTAssertGreaterThan(thick, thin, "thicker items should cast longer shadows")
    }

    func testNoShadowWhenOff() {
        let alpha = [UInt8](repeating: 255, count: 100)
        XCTAssertNil(ShadowModel.density(alpha: alpha, width: 10, height: 10, params: ShadowParams(kind: .none)))
    }

    // MARK: Colour

    func testLinearRoundTrip() {
        for v in 0..<256 {
            XCTAssertEqual(Int(Linear.toSRGB(Linear.toLinear[v])), v, accuracy: 1)
        }
    }

    func testBackdropFillsFrameWithoutDistortion() {
        // A 100 x 100 image covering a 300 x 150 frame is scaled to 300 wide and cropped.
        var src = RGBAImage(width: 100, height: 100, fill: (0, 0, 0))
        for y in 0..<100 { for x in 0..<50 { let i = (y * 100 + x) * 4; src.pixels[i] = 255 } }
        let cg = src.makeOpaqueCGImage()!
        let bg = Compositor.backdropImage(.image(cg), width: 300, height: 150)
        XCTAssertEqual(bg.width, 300)
        XCTAssertEqual(bg.height, 150)
        XCTAssertGreaterThan(bg.pixels[(75 * 300 + 100) * 4], 200)   // left half red
        XCTAssertLessThan(bg.pixels[(75 * 300 + 200) * 4], 50)       // right half black
    }

    // MARK: Touch-up brush

    func testSmartBrushStopsAtAColourEdge() {
        // Grey on the left, brown on the right; a restore stroke started on grey runs across both.
        let w = 120, h = 40
        let photo = stepImage(w: w, h: h, edgeX: 60, left: (150, 150, 150), right: (120, 80, 50))
        var alpha = [UInt8](repeating: 0, count: w * h)
        let ref = Brush.sample(photo, at: CGPoint(x: 30, y: 20), radius: 4)
        let stroke = BrushStroke(points: [CGPoint(x: 0.25, y: 0.5), CGPoint(x: 0.75, y: 0.5)], radius: 10 / 120,
                                 erase: false, reference: ref, tolerance: Brush.smartTolerance)
        Brush.apply([stroke], to: &alpha, width: w, height: h, photo: photo)
        XCTAssertEqual(alpha[20 * w + 40], 255, "grey restored")
        XCTAssertEqual(alpha[20 * w + 80], 0, "brown left alone")
        // The same stroke without the smart test paints both.
        var plain = [UInt8](repeating: 0, count: w * h)
        Brush.apply([BrushStroke(points: stroke.points, radius: stroke.radius, erase: false)], to: &plain, width: w, height: h)
        XCTAssertEqual(plain[20 * w + 80], 255)
    }

    func testBrushReplayMatchesLivePainting() {
        // The touch-up screen paints a dab, then piece by piece; Apply replays the stored stroke.
        let w = 256, h = 128   // powers of two, so the stored fractions are exact
        var live = [UInt8](repeating: 0, count: w * h)
        let pts = [CGPoint(x: 20, y: 30), CGPoint(x: 90, y: 60), CGPoint(x: 160, y: 40)]
        Brush.segment(&live, w, h, from: pts[0], to: pts[0], radius: 7, erase: false, gate: nil)
        Brush.segment(&live, w, h, from: pts[0], to: pts[1], radius: 7, erase: false, gate: nil)
        Brush.segment(&live, w, h, from: pts[1], to: pts[2], radius: 7, erase: false, gate: nil)
        var replay = [UInt8](repeating: 0, count: w * h)
        let s = BrushStroke(points: pts.map { CGPoint(x: $0.x / CGFloat(w), y: $0.y / CGFloat(h)) }, radius: 7 / 256, erase: false)
        Brush.apply([s], to: &replay, width: w, height: h)
        XCTAssertEqual(live, replay)
    }

    // MARK: Network input

    func testDarkPhotoIsBrightenedForTheNetworkAndGoodOneLeftAlone() {
        var dark = [UInt8](repeating: 255, count: 64 * 64 * 4)
        for i in 0..<(64 * 64) { let v = UInt8(10 + (i % 50)); dark[i * 4] = v; dark[i * 4 + 1] = v; dark[i * 4 + 2] = v }
        let lut = CutoutNetwork.exposureCurve(dark)
        XCTAssertNotNil(lut)
        if let lut { XCTAssertGreaterThan(Int(lut[35]), 90) }
        var good = [UInt8](repeating: 255, count: 64 * 64 * 4)
        for i in 0..<(64 * 64) { let v = UInt8(i % 256); good[i * 4] = v; good[i * 4 + 1] = v; good[i * 4 + 2] = v }
        XCTAssertNil(CutoutNetwork.exposureCurve(good))
    }

    func testNetworkAgreementCheck() {
        let a: [Float] = (0..<1000).map { $0 < 500 ? 4 : -4 }
        XCTAssertTrue(CutoutNetwork.agree(a, a))
        let b: [Float] = (0..<1000).map { $0 < 300 ? 4 : -4 }
        XCTAssertFalse(CutoutNetwork.agree(a, b))
        XCTAssertFalse(CutoutNetwork.agree(a.map { _ in Float.nan }, a))
    }

    // MARK: Second opinion

    func testDroppedPartIsRecoveredButShadowIsNot() {
        // Brown surface; the item is a dark block with a grey cuff below it the network missed,
        // and a shadow (darker brown) to its right that the subject finder also included.
        let w = 160, h = 160
        var img = RGBAImage(width: w, height: h, fill: (120, 80, 50))
        var prob = Plane(width: w, height: h, value: 0)
        var vision = Plane(width: w, height: h, value: 0)
        for y in 40..<100 { for x in 50..<110 {
            let i = y * w + x
            img.pixels[i * 4] = 25; img.pixels[i * 4 + 1] = 25; img.pixels[i * 4 + 2] = 28
            prob.data[i] = 1; vision.data[i] = 1
        } }
        for y in 100..<112 { for x in 50..<110 {
            let i = y * w + x
            img.pixels[i * 4] = 150; img.pixels[i * 4 + 1] = 150; img.pixels[i * 4 + 2] = 150
            vision.data[i] = 0.9
        } }
        for y in 40..<100 { for x in 110..<124 {
            let i = y * w + x
            img.pixels[i * 4] = 72; img.pixels[i * 4 + 1] = 48; img.pixels[i * 4 + 2] = 30
            vision.data[i] = 0.9
        } }
        _ = Segmenter.recoverParts(&prob, vision: vision, image: img)
        XCTAssertGreaterThan(prob.data[106 * w + 80], 0.5, "cuff recovered")
        XCTAssertLessThan(prob.data[70 * w + 117], 0.5, "shadow left out")
    }

    func testFalseHoleIsFilledButRealGapIsKept() {
        // Grey floor; a dark item with two non-solid patches inside it: one where the floor shows
        // through (a real gap) and one that is the item's own slightly lighter material.
        let w = 160, h = 160
        var R = Plane(width: w, height: h, value: 0.5), G = Plane(width: w, height: h, value: 0.5), B = Plane(width: w, height: h, value: 0.5)
        var prob = Plane(width: w, height: h, value: 0)
        for y in 30..<130 { for x in 30..<130 {
            let i = y * w + x
            R.data[i] = 0.12; G.data[i] = 0.11; B.data[i] = 0.10
            prob.data[i] = 1
        } }
        for y in 50..<62 { for x in 50..<62 {
            let i = y * w + x
            R.data[i] = 0.5; G.data[i] = 0.5; B.data[i] = 0.5
            prob.data[i] = 0
        } }
        for y in 90..<110 { for x in 80..<110 {
            let i = y * w + x
            R.data[i] = 0.18; G.data[i] = 0.16; B.data[i] = 0.14
            prob.data[i] = 0.3
        } }
        var fg = prob.data.map { $0 > 0.5 }
        let filled = Matting.fillFalseHoles(R: R, G: G, B: B, prob: &prob, fg: &fg)
        XCTAssertGreaterThan(filled, 0)
        XCTAssertEqual(prob.data[100 * w + 95], 1, "item material filled")
        XCTAssertLessThan(prob.data[56 * w + 56], 0.5, "real gap kept")
        XCTAssertEqual(prob.data[5 * w + 5], 0, "outside untouched")
    }

    func testGradientAndConnectivityCatchFeatheringAndBlotches() {
        let w = 80, h = 80
        var truth = [UInt8](repeating: 0, count: w * h)
        for y in 20..<60 { for x in 20..<60 { truth[y * w + x] = 255 } }
        XCTAssertEqual(Metrics.gradientError(truth, truth, w, h), 0, accuracy: 1e-9)
        XCTAssertEqual(Metrics.connectivityError(truth, truth, w, h), 0, accuracy: 1e-9)
        // Feathered: the same square, blurred.
        let feathered = Plane(bytes: truth, width: w, height: h).boxBlurred(radius: 4).toBytes()
        XCTAssertGreaterThan(Metrics.gradientError(feathered, truth, w, h), 0.001)
        // A separate solid speck outside the item, disconnected from it.
        var speck = truth
        for y in 5..<9 { for x in 5..<9 { speck[y * w + x] = 255 } }
        XCTAssertGreaterThan(Metrics.connectivityError(speck, truth, w, h), 0)
    }
}
