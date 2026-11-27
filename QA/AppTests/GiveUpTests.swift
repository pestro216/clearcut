import XCTest
@testable import Clearcut

/// When the automatic cutout gives up, the photo must not be a dead end: a starting cutout is
/// kept so it can be cut out by hand, while the original stays in use until someone chooses otherwise.
final class GiveUpTests: XCTestCase {
    func testAPhotoWithNoItemStillGetsAStartingCutout() throws {
        // A plain grey photo: nothing to find.
        let image = RGBAImage(width: 600, height: 800, fill: (128, 128, 128))
        let cg = try XCTUnwrap(image.makeOpaqueCGImage())
        let data = try XCTUnwrap(ImageIOHelpers.encode(cg, type: .jpeg))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let r = try XCTUnwrap(BatchStore.process(data: data, id: UUID(), dir: dir, surface: nil))
        guard case .failed = r.status else { return XCTFail("a plain photo should be flagged, got \(r.status)") }
        let alpha = try XCTUnwrap(r.alphaURL, "no starting cutout was kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: alpha.path))
        XCTAssertNotNil(r.previewAlphaURL)
        XCTAssertEqual(r.gridAlpha?.isEmpty, false)
        // Nothing was found, so the starting cutout keeps the whole photo, ready to erase from.
        XCTAssertEqual(BatchStore.readAlpha(alpha, width: 600, height: 800)?.min(), 255)
    }
}
