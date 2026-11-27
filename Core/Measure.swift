import Foundation

/// Measuring an item laid flat, using a sheet of A4 paper lying flat beside it as the ruler.
///
/// The sheet's four corners give a perspective map from the photo to the floor, in centimetres,
/// so the phone needn't be held exactly overhead. It is only right for things lying flat on the
/// same floor as the sheet, so every figure is shown as "about".
public enum Measure {
    public struct Point: Equatable {
        public var x: Double
        public var y: Double
        public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
        public func distance(to p: Point) -> Double { ((x - p.x) * (x - p.x) + (y - p.y) * (y - p.y)).squareRoot() }
    }

    public static let a4Long = 29.7
    public static let a4Short = 21.0

    /// A perspective map (3 x 3, row by row) from one plane to another.
    public struct Homography {
        public let m: [Double]

        /// The map taking the four `from` points to the four `to` points. nil if they are degenerate.
        public init?(from src: [Point], to dst: [Point]) {
            guard src.count == 4, dst.count == 4 else { return nil }
            // Eight equations in the eight unknowns h0...h7 (h8 = 1).
            var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
            for i in 0..<4 {
                let (x, y, u, v) = (src[i].x, src[i].y, dst[i].x, dst[i].y)
                a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
                a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
            }
            guard let h = Homography.solve(a) else { return nil }
            m = h + [1]
        }

        public func apply(_ p: Point) -> Point {
            let d = m[6] * p.x + m[7] * p.y + m[8]
            guard abs(d) > 1e-12 else { return Point(.infinity, .infinity) }
            return Point((m[0] * p.x + m[1] * p.y + m[2]) / d, (m[3] * p.x + m[4] * p.y + m[5]) / d)
        }

        /// Gaussian elimination with partial pivoting on an 8 x 9 augmented matrix.
        static func solve(_ input: [[Double]]) -> [Double]? {
            var a = input
            let n = 8
            for col in 0..<n {
                var pivot = col
                for r in (col + 1)..<n where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
                guard abs(a[pivot][col]) > 1e-12 else { return nil }
                a.swapAt(col, pivot)
                for r in 0..<n where r != col {
                    let f = a[r][col] / a[col][col]
                    if f == 0 { continue }
                    for c in col...n { a[r][c] -= f * a[col][c] }
                }
            }
            return (0..<n).map { a[$0][n] / a[$0][$0] }
        }
    }

    /// The map from photo pixels to centimetres on the floor, from the sheet's corners in photo
    /// pixels (top left, top right, bottom right, bottom left, as seen in the photo).
    public static func floorMap(sheet c: [Point]) -> Homography? {
        guard c.count == 4 else { return nil }
        let across = c[0].distance(to: c[1]) + c[3].distance(to: c[2])
        let down = c[0].distance(to: c[3]) + c[1].distance(to: c[2])
        let (w, h) = across >= down ? (a4Long, a4Short) : (a4Short, a4Long)
        return Homography(from: c, to: [Point(0, 0), Point(w, 0), Point(w, h), Point(0, h)])
    }

    public struct Result: Equatable {
        /// Top to bottom and side to side of the item on the floor, in centimetres.
        public var length: Double
        public var width: Double
        /// The ends of each, in photo pixels, for drawing.
        public var lengthEnds: (Point, Point)
        public var widthEnds: (Point, Point)
        /// How much of the sheet the cutout covers (0...1). High means the sheet was cut out with the item.
        public var sheetCovered: Double

        public static func == (a: Result, b: Result) -> Bool {
            a.length == b.length && a.width == b.width && a.sheetCovered == b.sheetCovered
        }
    }

    /// Length and width of the item in a matte, measured on the floor. The sheet is ignored even if
    /// the matte includes it.
    public static func item(alpha: [UInt8], width w: Int, height h: Int, sheet: [Point]) -> Result? {
        guard alpha.count == w * h, let map = floorMap(sheet: sheet) else { return nil }
        let inside = Quad(sheet)
        var minY = Double.infinity, maxY = -Double.infinity, minX = Double.infinity, maxX = -Double.infinity
        var ends = (top: Point(0, 0), bottom: Point(0, 0), left: Point(0, 0), right: Point(0, 0))
        var sheetPixels = 0, sheetCovered = 0
        let step = max(1, max(w, h) / 900)
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                let p = Point(Double(x) + 0.5, Double(y) + 0.5)
                let onItem = alpha[y * w + x] >= 128
                if inside.contains(p) {
                    sheetPixels += 1
                    if onItem { sheetCovered += 1 }
                } else if onItem {
                    let f = map.apply(p)
                    if f.x.isFinite && f.y.isFinite {
                        if f.y < minY { minY = f.y; ends.top = p }
                        if f.y > maxY { maxY = f.y; ends.bottom = p }
                        if f.x < minX { minX = f.x; ends.left = p }
                        if f.x > maxX { maxX = f.x; ends.right = p }
                    }
                }
                x += step
            }
            y += step
        }
        guard maxY > minY, maxX > minX else { return nil }
        // Floor axes follow the sheet; an item laid at an angle to it is measured along the sheet's edges.
        return Result(length: maxY - minY, width: maxX - minX, lengthEnds: (ends.top, ends.bottom),
                      widthEnds: (ends.left, ends.right),
                      sheetCovered: sheetPixels == 0 ? 0 : Double(sheetCovered) / Double(sheetPixels))
    }

    /// Distance on the floor between two photo points, in centimetres.
    public static func distance(_ a: Point, _ b: Point, sheet: [Point]) -> Double? {
        guard let map = floorMap(sheet: sheet) else { return nil }
        let d = map.apply(a).distance(to: map.apply(b))
        return d.isFinite ? d : nil
    }

    /// A convex four-sided shape, for testing whether a point lies on the sheet.
    struct Quad {
        let c: [Point]
        init(_ c: [Point]) { self.c = c }
        func contains(_ p: Point) -> Bool {
            var sign = 0
            for i in 0..<4 {
                let a = c[i], b = c[(i + 1) % 4]
                let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
                let s = cross > 0 ? 1 : (cross < 0 ? -1 : 0)
                if s == 0 { continue }
                if sign == 0 { sign = s } else if s != sign { return false }
            }
            return true
        }
    }

    /// "about 62 cm", to the nearest half centimetre.
    public static func text(_ cm: Double) -> String {
        let r = (cm * 2).rounded() / 2
        return r == r.rounded() ? "about \(Int(r)) cm" : String(format: "about %.1f cm", r)
    }
}
