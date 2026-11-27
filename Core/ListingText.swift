import Foundation

/// What a listing says about an item. Every field is filled only from what was read off the
/// photos (labels, the cutout's colour, a measurement) and can be edited. Nothing is guessed:
/// an empty field stays empty.
public struct ListingFacts: Codable, Equatable {
    public var brand = ""
    public var kind = ""
    public var colour = ""
    public var size = ""
    public var materials = ""
    public var length = ""
    public var width = ""
    public var condition = ""

    public init() {}

    /// A title in the usual reseller order: brand, colour, kind, size. Kept to 80 characters (eBay's limit).
    public var title: String {
        var parts = [brand, colour, kind].filter { !$0.isEmpty }
        if !size.isEmpty { parts.append("size \(size)") }
        let t = parts.joined(separator: " ")
        return t.count <= 80 ? t : String(t.prefix(80))
    }

    /// A plain description from the facts alone.
    public var text: String {
        var lines: [String] = []
        let what = [colour, kind].filter { !$0.isEmpty }.joined(separator: " ")
        if !brand.isEmpty || !what.isEmpty {
            lines.append([brand, what.isEmpty ? "" : what.lowercased()].filter { !$0.isEmpty }.joined(separator: " ") + ".")
        }
        if !size.isEmpty { lines.append("Size: \(size)") }
        if !materials.isEmpty { lines.append("Material: \(materials)") }
        var m: [String] = []
        if !length.isEmpty { m.append("length \(length)") }
        if !width.isEmpty { m.append("width \(width)") }
        if !m.isEmpty { lines.append("Measured laid flat: " + m.joined(separator: ", ") + ".") }
        lines.append("Condition: \(condition)")
        return lines.joined(separator: "\n")
    }
}

/// Reads sizes, fibres and a likely brand from the text on clothing labels.
public enum LabelReader {
    /// One line of text found in a photo, with how tall it is (0...1 of the photo's height).
    public struct Line {
        public var text: String
        public var height: Double
        public init(_ text: String, height: Double) { self.text = text; self.height = height }
    }

    public static func facts(from lines: [Line]) -> ListingFacts {
        var f = ListingFacts()
        f.size = size(in: lines.map(\.text))
        f.materials = materials(in: lines.map(\.text))
        f.brand = brand(in: lines)
        return f
    }

    // MARK: Size

    static let letterSizes = ["XXXS", "XXS", "XS", "S", "M", "L", "XL", "XXL", "XXXL", "2XL", "3XL", "4XL", "5XL"]
    static let sizeWords = ["SIZE", "TAILLE", "GRÖSSE", "GROSSE", "GRÖßE", "TALLA", "TAGLIA", "ROZMIAR", "MAAT", "TAMANHO", "STORLEK"]

    public static func size(in texts: [String]) -> String {
        let upper = texts.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        // "SIZE 12", "Taille: M", "Größe 40"
        for t in upper {
            for w in sizeWords {
                guard let r = t.range(of: w) else { continue }
                let rest = t[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " :/.-"))
                let token = rest.split(separator: " ").first.map(String.init) ?? ""
                if isSize(token) { return token }
            }
        }
        // "W32 L34", "32W 30L"
        for t in upper {
            if let m = firstMatch(#"\bW\s?(\d{2})\s*L\s?(\d{2})\b"#, in: t) { return "W\(m[0]) L\(m[1])" }
            if let m = firstMatch(#"\b(\d{2})\s?W\s*(\d{2})\s?L\b"#, in: t) { return "W\(m[0]) L\(m[1])" }
        }
        // "UK 12", "EU 40", "US 8"
        for t in upper {
            if let m = firstMatch(#"\b(UK|EU|EUR|US|FR|IT|DE)\s?(\d{1,2})\b"#, in: t) {
                return "\(m[0] == "EUR" ? "EU" : m[0]) \(m[1])"
            }
        }
        // A label line that is only a letter size.
        for t in upper where letterSizes.contains(t) { return t }
        return ""
    }

    static func isSize(_ s: String) -> Bool {
        if letterSizes.contains(s) { return true }
        if let n = Int(s), (0...60).contains(n) { return true }
        return false
    }

    // MARK: Materials

    /// Fibre names in the languages labels are printed in, mapped to English.
    static let fibres: [String: String] = {
        var m: [String: String] = [:]
        let table: [(String, [String])] = [
            ("cotton", ["cotton", "coton", "baumwolle", "algodón", "algodon", "cotone", "bawełna", "bawelna", "katoen", "algodão"]),
            ("polyester", ["polyester", "poliéster", "poliester", "poliestere", "polyesteri"]),
            ("wool", ["wool", "laine", "wolle", "lana", "wełna", "welna", "wol", "lã"]),
            ("merino wool", ["merino"]),
            ("elastane", ["elastane", "elasthan", "elastan", "elastano", "spandex", "lycra"]),
            ("viscose", ["viscose", "viskose", "viscosa", "wiskoza", "rayon"]),
            ("polyamide", ["polyamide", "polyamid", "poliamida", "poliammide", "poliamid", "nylon"]),
            ("acrylic", ["acrylic", "acrylique", "polyacryl", "acrílico", "acrilico", "akryl", "acryl"]),
            ("linen", ["linen", "lin", "leinen", "lino", "len", "linnen", "linho"]),
            ("silk", ["silk", "soie", "seide", "seda", "seta", "jedwab", "zijde"]),
            ("cashmere", ["cashmere", "cachemire", "kaschmir", "cachemira", "kaszmir"]),
            ("leather", ["leather", "cuir", "leder", "cuero", "pelle", "skóra", "skora", "leer"]),
            ("down", ["down", "duvet", "daunen", "plumón", "piumino", "puch"]),
            ("feather", ["feather", "plume", "plumes", "federn", "pluma", "piuma", "pierze"]),
            ("modal", ["modal"]),
            ("lyocell", ["lyocell", "tencel"]),
            ("alpaca", ["alpaca", "alpaka"]),
            ("mohair", ["mohair", "moher"]),
            ("angora", ["angora"]),
            ("polyurethane", ["polyurethane", "polyurethan", "poliuretano", "polyuréthane", "pu"]),
        ]
        for (english, names) in table { for n in names { m[n] = english } }
        return m
    }()

    public static func materials(in texts: [String]) -> String {
        var found: [(fibre: String, percent: Int)] = []
        @discardableResult func add(_ word: String, _ pct: String) -> Bool {
            guard let fibre = fibres[word.lowercased()], let p = Int(pct), (1...100).contains(p) else { return false }
            if !found.contains(where: { $0.fibre == fibre }) { found.append((fibre, p)) }
            return true
        }
        let percentFirst = #"(\d{1,3})\s?%\s?([\p{L}]+)"#, wordFirst = #"([\p{L}]+)\s?(\d{1,3})\s?%"#
        for t in texts {
            // "80% cotton 20% polyester" or "cotton 80% polyester 20%": the line's first character
            // says which way round it is written, so a number is never paired with the wrong fibre.
            let startsWithNumber = t.trimmingCharacters(in: .whitespaces).first?.isNumber ?? false
            var any = false
            if startsWithNumber {
                for m in allMatches(percentFirst, in: t) where add(m[1], m[0]) { any = true }
                if !any { for m in allMatches(wordFirst, in: t) { add(m[0], m[1]) } }
            } else {
                for m in allMatches(wordFirst, in: t) where add(m[0], m[1]) { any = true }
                if !any { for m in allMatches(percentFirst, in: t) { add(m[1], m[0]) } }
            }
        }
        // Labels list the same mix in several languages; the first reading of each fibre is kept.
        // A total well over 100 means several parts (shell, lining), so the order found is kept.
        let total = found.reduce(0) { $0 + $1.percent }
        let list = total <= 100 ? found.sorted { $0.percent > $1.percent } : found
        return list.map { "\($0.percent)% \($0.fibre)" }.joined(separator: ", ")
    }

    // MARK: Brand

    /// Words that appear on labels but are never the brand.
    static let notBrand: Set<String> = [
        "SIZE", "MADE", "IN", "CHINA", "BANGLADESH", "INDIA", "TURKEY", "VIETNAM", "CAMBODIA", "PAKISTAN", "PORTUGAL", "ITALY",
        "WASH", "DRY", "CLEAN", "IRON", "DO", "NOT", "BLEACH", "TUMBLE", "HAND", "MACHINE", "COLD", "WARM", "INSIDE", "OUT",
        "COTTON", "POLYESTER", "WOOL", "VISCOSE", "ELASTANE", "NYLON", "POLYAMIDE", "LINING", "SHELL", "FILLING", "BODY",
        "RN", "CA", "STYLE", "COLOUR", "COLOR", "CARE", "LABEL", "ONLY", "WITH", "SIMILAR", "COLOURS", "COLORS", "AND", "THE",
        "UK", "EU", "US", "FR", "IT", "DE", "TAILLE", "GRÖSSE", "TALLA", "TAGLIA", "FABRIQUÉ", "HERGESTELLT",
    ]

    /// The likely brand: the largest line of lettering that reads like a name, not label wording.
    public static func brand(in lines: [Line]) -> String {
        let candidates = lines.filter { line in
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...24).contains(t.count) else { return false }
            let letters = t.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            guard Double(letters) >= Double(t.count) * 0.6 else { return false }
            if t.contains("%") { return false }
            let words = t.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            if words.isEmpty || words.allSatisfy({ notBrand.contains($0) }) { return false }
            if letterSizes.contains(t.uppercased()) { return false }
            return true
        }
        guard let best = candidates.max(by: { $0.height < $1.height }) else { return "" }
        let t = best.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // All-capitals lettering is shown in title case, except short names (initials).
        if t == t.uppercased() && t.count > 4 { return t.capitalized }
        return t
    }

    // MARK: Matching helpers

    static func firstMatch(_ pattern: String, in s: String) -> [String]? { allMatches(pattern, in: s).first }

    static func allMatches(_ pattern: String, in s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }
}

/// Names the main colour of an item from its average colour (sRGB, 0...1).
public enum ColourName {
    public static func name(r: Double, g: Double, b: Double) -> String {
        let mx = max(r, g, b), mn = min(r, g, b)
        let light = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let sat = mx == 0 ? 0 : (mx - mn) / mx
        var hue = 0.0
        if mx > mn {
            if mx == r { hue = 60 * (((g - b) / (mx - mn)).truncatingRemainder(dividingBy: 6)) }
            else if mx == g { hue = 60 * ((b - r) / (mx - mn) + 2) }
            else { hue = 60 * ((r - g) / (mx - mn) + 4) }
        }
        if hue < 0 { hue += 360 }
        if light < 0.07 || (mx < 0.16) { return "Black" }
        if sat < 0.14 {
            if light > 0.82 { return "White" }
            if light > 0.55 { return "Light grey" }
            if light > 0.25 { return "Grey" }
            return "Charcoal"
        }
        switch hue {
        case 0..<14, 345...360:
            if light < 0.12 { return "Burgundy" }
            return sat < 0.4 && light > 0.5 ? "Pink" : "Red"
        case 14..<42:
            if light < 0.25 { return "Brown" }
            if sat < 0.45 && light > 0.5 { return "Beige" }
            if light < 0.4 { return "Tan" }
            return "Orange"
        case 42..<68:
            if sat < 0.45 && light > 0.55 { return "Cream" }
            if light < 0.35 { return "Khaki" }
            return "Yellow"
        case 68..<165:
            if light < 0.2 || (sat < 0.4 && light < 0.4) { return "Olive" }
            return "Green"
        case 165..<200:
            return "Teal"
        case 200..<255:
            if light < 0.12 { return "Navy" }
            return light > 0.55 ? "Light blue" : "Blue"
        case 255..<290:
            return light > 0.5 ? "Lilac" : "Purple"
        default:
            return light < 0.2 ? "Plum" : "Pink"
        }
    }
}
