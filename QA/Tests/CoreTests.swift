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
}
