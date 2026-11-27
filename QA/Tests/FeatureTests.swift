import XCTest
@testable import ClearcutCore

/// Tests for the 27 Nov 2026 experiments: hanger hook removal, measuring against A4, label reading.
final class FeatureTests: XCTestCase {

    // MARK: Hanger hook

    /// A garment-like block with an optional thin hook above its middle.
    func garment(w: Int = 200, h: Int = 300, hook: Bool, hookWidth: Int = 4) -> [UInt8] {
        var a = [UInt8](repeating: 0, count: w * h)
        for y in 80..<280 { for x in 30..<170 { a[y * w + x] = 255 } }
        if hook {
            for y in 40..<80 { for x in (100 - hookWidth / 2)..<(100 + hookWidth / 2) { a[y * w + x] = 255 } }
        }
        return a
    }

    func testHookIsFoundAndCleared() throws {
        let a = garment(hook: true)
        let f = try XCTUnwrap(Hanger.find(alpha: a, width: 200, height: 300))
        XCTAssertEqual(f.top, 40)
        XCTAssertEqual(f.cut, 80)
        let out = try XCTUnwrap(Hanger.removed(alpha: a, width: 200, height: 300))
        for y in 0..<80 { for x in 0..<200 { XCTAssertEqual(out[y * 200 + x], 0) } }
        // The item itself is untouched.
        for y in 80..<280 { for x in 30..<170 { XCTAssertEqual(out[y * 200 + x], 255) } }
    }

    func testNoHookNoChange() {
        XCTAssertNil(Hanger.find(alpha: garment(hook: false), width: 200, height: 300))
    }

    func testPointedTopIsNotAHook() {
        // A triangle on top of the block (a hood's peak, a bottle neck widening steadily).
        let w = 200, h = 300
        var a = garment(hook: false)
        for y in 20..<80 {
            let half = (y - 20) * 70 / 60
            for x in max(0, 100 - half)..<min(w, 100 + half + 1) { a[y * w + x] = 255 }
        }
        XCTAssertNil(Hanger.find(alpha: a, width: w, height: h))
    }

    func testOffCentreStrapIsNotAHook() {
        let w = 200, h = 300
        var a = garment(hook: false)
        for y in 40..<80 { for x in 34..<38 { a[y * w + x] = 255 } }
        XCTAssertNil(Hanger.find(alpha: a, width: w, height: h))
    }

    // MARK: Measuring

    func testSheetSeenSquareOnGivesTrueSizes() throws {
        // 10 pixels per centimetre, sheet upright (21 x 29.7 cm), item 50 x 70 cm beside it.
        let w = 1000, h = 900
        let sheet = [Measure.Point(50, 50), Measure.Point(260, 50), Measure.Point(260, 347), Measure.Point(50, 347)]
        var a = [UInt8](repeating: 0, count: w * h)
        for y in 100..<800 { for x in 400..<900 { a[y * w + x] = 255 } }
        let r = try XCTUnwrap(Measure.item(alpha: a, width: w, height: h, sheet: sheet))
        XCTAssertEqual(r.length, 70, accuracy: 0.6)
        XCTAssertEqual(r.width, 50, accuracy: 0.6)
        XCTAssertLessThan(r.sheetCovered, 0.01)
        let d = try XCTUnwrap(Measure.distance(Measure.Point(400, 100), Measure.Point(900, 100), sheet: sheet))
        XCTAssertEqual(d, 50, accuracy: 0.1)
    }

    func testHomographyMapsCornersExactly() throws {
        let src = [Measure.Point(12, 30), Measure.Point(410, 52), Measure.Point(380, 600), Measure.Point(5, 560)]
        let dst = [Measure.Point(0, 0), Measure.Point(21, 0), Measure.Point(21, 29.7), Measure.Point(0, 29.7)]
        let hmg = try XCTUnwrap(Measure.Homography(from: src, to: dst))
        for (s, d) in zip(src, dst) {
            let p = hmg.apply(s)
            XCTAssertEqual(p.x, d.x, accuracy: 1e-6)
            XCTAssertEqual(p.y, d.y, accuracy: 1e-6)
        }
    }

    func testLandscapeSheetUsesLongSideAcross() throws {
        let sheet = [Measure.Point(0, 0), Measure.Point(297, 0), Measure.Point(297, 210), Measure.Point(0, 210)]
        let d = try XCTUnwrap(Measure.distance(Measure.Point(0, 0), Measure.Point(297, 0), sheet: sheet))
        XCTAssertEqual(d, 29.7, accuracy: 1e-6)
    }

    func testMeasureText() {
        XCTAssertEqual(Measure.text(61.8), "about 62 cm")
        XCTAssertEqual(Measure.text(54.3), "about 54.5 cm")
    }

    // MARK: Labels

    func testSizeAndMaterialsFromAMultilingualLabel() {
        let lines = ["SIZE M", "80% COTTON", "20% POLYESTER", "80% COTON", "20% POLYESTER", "80% BAUMWOLLE", "MADE IN PORTUGAL"]
        XCTAssertEqual(LabelReader.size(in: lines), "M")
        XCTAssertEqual(LabelReader.materials(in: lines), "80% cotton, 20% polyester")
        XCTAssertEqual(LabelReader.materials(in: ["COTTON 80% POLYESTER 20%"]), "80% cotton, 20% polyester")
    }

    func testOtherSizeForms() {
        XCTAssertEqual(LabelReader.size(in: ["W32 L34"]), "W32 L34")
        XCTAssertEqual(LabelReader.size(in: ["UK 12 EUR 40"]), "UK 12")
        XCTAssertEqual(LabelReader.size(in: ["Taille: 38"]), "38")
        XCTAssertEqual(LabelReader.size(in: ["XL"]), "XL")
        XCTAssertEqual(LabelReader.size(in: ["OVERSIZED FIT"]), "")
    }

    func testBrandIsTheLargestNameLikeLine() {
        let lines = [LabelReader.Line("COLUMBIA", height: 0.08), LabelReader.Line("MADE IN VIETNAM", height: 0.02),
                     LabelReader.Line("100% NYLON", height: 0.03), LabelReader.Line("M", height: 0.1)]
        XCTAssertEqual(LabelReader.brand(in: lines), "Columbia")
    }

    func testNothingInventedFromNothing() {
        let f = LabelReader.facts(from: [])
        XCTAssertEqual(f, ListingFacts())
        XCTAssertEqual(f.title, "")
    }

    func testTitleOrder() {
        var f = ListingFacts()
        f.brand = "Columbia"; f.colour = "Navy"; f.kind = "Jacket"; f.size = "M"
        XCTAssertEqual(f.title, "Columbia Navy Jacket size M")
    }

    func testColourNames() {
        XCTAssertEqual(ColourName.name(r: 0.02, g: 0.02, b: 0.02), "Black")
        XCTAssertEqual(ColourName.name(r: 0.95, g: 0.95, b: 0.95), "White")
        XCTAssertEqual(ColourName.name(r: 0.05, g: 0.08, b: 0.25), "Navy")
        XCTAssertEqual(ColourName.name(r: 0.8, g: 0.1, b: 0.1), "Red")
        XCTAssertEqual(ColourName.name(r: 0.2, g: 0.5, b: 0.2), "Green")
    }
}
