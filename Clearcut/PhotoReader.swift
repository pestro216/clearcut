import UIKit
import Vision

/// Reads what a listing needs from the batch's photos, all on the phone with Apple's Vision:
/// label text, what kind of item it is, its main colour, and an A4 sheet to measure against.
enum PhotoReader {
    /// Lines of text in a photo (labels, tags), with their size.
    static func lines(in url: URL) -> [LabelReader.Line] {
        autoreleasepool {
            guard let data = try? Data(contentsOf: url), let cg = ImageIOHelpers.loadOriented(data, maxPixel: 3000) else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Brand names aren't dictionary words, so no autocorrection.
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            return (request.results ?? []).compactMap { o in
                guard let s = o.topCandidates(1).first?.string else { return nil }
                return LabelReader.Line(s, height: Double(o.boundingBox.height))
            }
        }
    }

    /// Vision's image classes that name an item, in the words resellers use.
    static let kinds: [String: String] = [
        "jacket": "Jacket", "coat": "Coat", "raincoat": "Raincoat", "jeans": "Jeans", "shirt": "Shirt", "t_shirt": "T-shirt",
        "tshirt": "T-shirt", "sweater": "Jumper", "sweatshirt": "Sweatshirt", "hoodie": "Hoodie", "cardigan": "Cardigan",
        "dress": "Dress", "skirt": "Skirt", "shorts": "Shorts", "trousers": "Trousers", "pants": "Trousers", "blouse": "Blouse",
        "vest": "Vest", "suit": "Suit", "jumpsuit": "Jumpsuit", "shoes": "Shoes", "shoe": "Shoes", "sneaker": "Trainers",
        "sneakers": "Trainers", "boot": "Boots", "boots": "Boots", "sandal": "Sandals", "sandals": "Sandals", "handbag": "Handbag",
        "bag": "Bag", "backpack": "Backpack", "purse": "Purse", "wallet": "Wallet", "hat": "Hat", "cap": "Cap", "beanie": "Beanie",
        "scarf": "Scarf", "gloves": "Gloves", "glove": "Gloves", "belt": "Belt", "sunglasses": "Sunglasses", "watch": "Watch",
        "necklace": "Necklace", "bracelet": "Bracelet", "earring": "Earrings", "tie": "Tie", "swimsuit": "Swimsuit",
        "bikini": "Bikini", "uniform": "Uniform", "kimono": "Kimono", "poncho": "Poncho", "apron": "Apron",
    ]

    /// What kind of item a photo shows, or "" when Vision isn't sure.
    static func kind(of cg: CGImage) -> String {
        let request = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        let results = (request.results ?? []).filter { $0.confidence > 0.2 }.sorted { $0.confidence > $1.confidence }
        for o in results { if let k = kinds[o.identifier.lowercased()] { return k } }
        return ""
    }

    /// The main colour of the item: the average of the pixels that are clearly item.
    static func colour(photo: RGBAImage, alpha: [UInt8]) -> String {
        guard alpha.count == photo.width * photo.height else { return "" }
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        var i = 0
        while i < alpha.count {
            if alpha[i] >= 220 {
                r += Double(photo.pixels[i * 4]); g += Double(photo.pixels[i * 4 + 1]); b += Double(photo.pixels[i * 4 + 2]); n += 1
            }
            i += 3
        }
        guard n > 50 else { return "" }
        return ColourName.name(r: r / n / 255, g: g / n / 255, b: b / n / 255)
    }

    /// Facts from the photos of one item: text from all of them, kind and colour from the first.
    static func read(texts: [URL], front: (photo: URL, alpha: URL?)) -> ListingFacts {
        var lines: [LabelReader.Line] = []
        for u in texts { lines += PhotoReader.lines(in: u) }
        var facts = LabelReader.facts(from: lines)
        autoreleasepool {
            guard let data = try? Data(contentsOf: front.photo), let cg = ImageIOHelpers.loadOriented(data, maxPixel: 1100),
                  let photo = RGBAImage(cgImage: cg) else { return }
            facts.kind = kind(of: cg)
            if let au = front.alpha, let alpha = BatchStore.readAlpha(au, width: photo.width, height: photo.height) {
                facts.colour = colour(photo: photo, alpha: alpha)
            }
        }
        return facts
    }

    // MARK: A4 sheet

    /// The corners of a white A4 sheet in the photo, in its pixels (top left, top right, bottom
    /// right, bottom left), or nil when there isn't one.
    static func sheet(in cg: CGImage, photo: RGBAImage) -> [Measure.Point]? {
        let request = VNDetectRectanglesRequest()
        // A4 is 0.707 short side to long; seen at a slant it can look a little squarer or thinner.
        request.minimumAspectRatio = 0.55
        request.maximumAspectRatio = 0.85
        request.minimumSize = 0.08
        request.maximumObservations = 8
        request.minimumConfidence = 0.5
        request.quadratureTolerance = 25
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        let w = Double(cg.width), h = Double(cg.height)
        func px(_ p: CGPoint) -> Measure.Point { Measure.Point(Double(p.x) * w, (1 - Double(p.y)) * h) }
        var best: (corners: [Measure.Point], score: Double)?
        for o in request.results ?? [] {
            let c = [px(o.topLeft), px(o.topRight), px(o.bottomRight), px(o.bottomLeft)]
            let look = paperLook(photo, corners: c)
            // Paper is light and nearly colourless.
            guard look.light > 0.5, look.sat < 0.25 else { continue }
            let score = Double(o.confidence) + look.light
            if best == nil || score > best!.score { best = (c, score) }
        }
        return best?.corners
    }

    /// Average lightness and saturation inside a four-cornered area.
    private static func paperLook(_ photo: RGBAImage, corners c: [Measure.Point]) -> (light: Double, sat: Double) {
        var light = 0.0, sat = 0.0, n = 0.0
        for a in stride(from: 0.2, through: 0.8, by: 0.1) {
            for b in stride(from: 0.2, through: 0.8, by: 0.1) {
                let top = Measure.Point(c[0].x + (c[1].x - c[0].x) * a, c[0].y + (c[1].y - c[0].y) * a)
                let bottom = Measure.Point(c[3].x + (c[2].x - c[3].x) * a, c[3].y + (c[2].y - c[3].y) * a)
                let x = Int(top.x + (bottom.x - top.x) * b), y = Int(top.y + (bottom.y - top.y) * b)
                guard x >= 0, y >= 0, x < photo.width, y < photo.height else { continue }
                let i = (y * photo.width + x) * 4
                let r = Double(photo.pixels[i]) / 255, g = Double(photo.pixels[i + 1]) / 255, bl = Double(photo.pixels[i + 2]) / 255
                let mx = max(r, g, bl), mn = min(r, g, bl)
                light += 0.2126 * r + 0.7152 * g + 0.0722 * bl
                sat += mx == 0 ? 0 : (mx - mn) / mx
                n += 1
            }
        }
        return n == 0 ? (0, 1) : (light / n, sat / n)
    }
}
