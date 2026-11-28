import Foundation

/// Spreads image loops over the CPU cores in bands of rows (or columns).
///
/// Every band does exactly the arithmetic the single-thread loop would do for its part, in the
/// same order, and bands never write to the same place. So the result is the same, bit for bit,
/// whatever the number of threads. No band holds extra image-sized buffers: threading costs no
/// memory beyond a row or two per band.
public enum Parallel {
    /// Threads to use. 1 runs every loop on the calling thread (the tests compare both).
    nonisolated(unsafe) public static var threads = max(1, ProcessInfo.processInfo.activeProcessorCount)

    /// Calls `body` with consecutive ranges that together cover `0..<count`, on several cores when
    /// there are at least two bands of `grain` items. A few bands per core, so a slow core (the
    /// iPhone's efficiency cores) doesn't hold up the rest.
    @inline(__always)
    public static func forBands(_ count: Int, grain: Int, _ body: (Range<Int>) -> Void) {
        guard count > 0 else { return }
        let t = threads
        let bands = min(t * 3, count / max(1, grain))
        if t <= 1 || bands <= 1 { body(0..<count); return }
        DispatchQueue.concurrentPerform(iterations: bands) { k in
            body((count * k / bands)..<(count * (k + 1) / bands))
        }
    }

    /// Rows per band so that each band has at least about 32 000 pixels of work.
    @inline(__always)
    public static func rowGrain(width: Int) -> Int { max(1, 32_768 / max(1, width)) }
}

/// The four neighbours and weights of one bilinear sample, worked out once and then read from
/// several planes of the same size. Same arithmetic as `Plane.sample`, which uses it.
struct Bilinear {
    let i: Int, dx: Int, dy: Int
    let tx: Float, ty: Float

    /// Continuous coordinates, pixel centres at integer + 0.5.
    @inline(__always) init(_ fx: Float, _ fy: Float, width: Int, height: Int) {
        let x = max(0, min(max(0, Float(width) - 1.001), fx - 0.5))
        let y = max(0, min(max(0, Float(height) - 1.001), fy - 0.5))
        let x0 = Int(x), y0 = Int(y)
        tx = x - Float(x0); ty = y - Float(y0)
        i = y0 * width + x0
        dx = x0 + 1 < width ? 1 : 0
        dy = y0 + 1 < height ? width : 0
    }

    @inline(__always) func read(_ d: UnsafePointer<Float>) -> Float {
        let a = d[i], b = d[i + dx], c = d[i + dy], e = d[i + dy + dx]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + e * tx) * ty
    }

    @inline(__always) func read(_ d: [Float]) -> Float {
        let a = d[i], b = d[i + dx], c = d[i + dy], e = d[i + dy + dx]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + e * tx) * ty
    }
}

extension Array where Element == Plane {
    /// Base pointers to each plane's pixels, valid only inside `body`.
    func withPixelPointers<R>(_ body: ([UnsafePointer<Float>]) -> R) -> R {
        var ptrs: [UnsafePointer<Float>] = []
        ptrs.reserveCapacity(count)
        func go(_ k: Int) -> R {
            if k == count { return body(ptrs) }
            return self[k].data.withUnsafeBufferPointer { b -> R in
                // An empty plane is never read; any non-nil pointer will do.
                ptrs.append(b.baseAddress ?? UnsafePointer(bitPattern: 16)!)
                return go(k + 1)
            }
        }
        return go(0)
    }
}
