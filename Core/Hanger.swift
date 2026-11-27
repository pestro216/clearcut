import Foundation

/// Finds the hook of a hanger sticking up out of a garment's cutout, so it can be cleared.
///
/// Experiment (27 Nov 2026). A general rule, not tuned to any photo: seen row by row from the
/// top, a hook is a run of rows that are all very narrow compared with the item, that doesn't
/// widen steadily the way a pointed shape does, and that ends in a sudden jump to the item's
/// width (the shoulders or the hanger's bar). Anything else is left alone.
public enum Hanger {
    public struct Found: Equatable {
        /// First row of the hook and the row where the item proper starts (cleared rows: top..<cut).
        public let top: Int
        public let cut: Int
        /// Columns the hook covers.
        public let minX: Int
        public let maxX: Int
    }

    public static func find(alpha: [UInt8], width w: Int, height h: Int) -> Found? {
        guard w > 8, h > 8, alpha.count == w * h else { return nil }
        var count = [Int](repeating: 0, count: h)
        var lo = [Int](repeating: Int.max, count: h)
        var hi = [Int](repeating: -1, count: h)
        for y in 0..<h {
            let base = y * w
            var c = 0, mn = Int.max, mx = -1
            for x in 0..<w where alpha[base + x] >= 128 {
                c += 1
                if mn == Int.max { mn = x }
                mx = x
            }
            count[y] = c; lo[y] = mn; hi[y] = mx
        }
        guard let top = count.firstIndex(where: { $0 > 0 }), let bottom = count.lastIndex(where: { $0 > 0 }) else { return nil }
        let itemH = bottom - top + 1
        guard itemH >= 40 else { return nil }

        // The item's usual width: the median row of its middle half.
        let middle = count[(top + itemH / 4)...(top + 3 * itemH / 4)].filter { $0 > 0 }.sorted()
        guard !middle.isEmpty else { return nil }
        let body = middle[middle.count / 2]
        guard body >= 30 else { return nil }
        let thin = max(2, body * 8 / 100)
        let wide = max(thin + 1, body * 20 / 100)

        var cut = top
        while cut <= bottom && count[cut] <= thin { cut += 1 }
        let rows = cut - top
        guard rows >= max(4, itemH * 3 / 100), rows <= itemH * 35 / 100, cut < bottom else { return nil }

        // A pointed top widens steadily from nothing; a hook stays about as thin all the way down.
        let quarter = max(1, rows / 4)
        let first = count[top..<(top + quarter)].reduce(0, +) / quarter
        let last = count[(cut - quarter)..<cut].reduce(0, +) / quarter
        guard last <= first * 3 / 2 + 2 else { return nil }

        // It must end in a jump: the item's width is reached within a few rows.
        let jump = max(3, itemH * 4 / 100)
        guard (cut..<min(bottom + 1, cut + jump)).contains(where: { count[$0] >= wide }) else { return nil }

        // Near the item's middle, side to side.
        var minX = Int.max, maxX = -1
        for y in top..<cut where count[y] > 0 { minX = min(minX, lo[y]); maxX = max(maxX, hi[y]) }
        guard maxX >= minX else { return nil }
        var bodyLo = Int.max, bodyHi = -1
        for y in (top + itemH / 4)...(top + 3 * itemH / 4) where count[y] > 0 { bodyLo = min(bodyLo, lo[y]); bodyHi = max(bodyHi, hi[y]) }
        let centre = Double(bodyLo + bodyHi) / 2, hookCentre = Double(minX + maxX) / 2
        guard abs(hookCentre - centre) <= Double(bodyHi - bodyLo) * 0.25 else { return nil }

        return Found(top: top, cut: cut, minX: minX, maxX: maxX)
    }

    /// The matte with the hook cleared, or nil when no hook is found.
    public static func removed(alpha: [UInt8], width w: Int, height h: Int) -> [UInt8]? {
        guard let f = find(alpha: alpha, width: w, height: h) else { return nil }
        var out = alpha
        let pad = max(4, (f.maxX - f.minX) / 2 + w / 100)
        let x0 = max(0, f.minX - pad), x1 = min(w - 1, f.maxX + pad)
        // Everything above the item proper in the hook's columns, soft edges included.
        // The item itself (from the cut row down) is never touched.
        for y in 0..<f.cut { let base = y * w; for x in x0...x1 { out[base + x] = 0 } }
        return out
    }
}
