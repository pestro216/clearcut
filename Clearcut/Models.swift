import SwiftUI
import UIKit

enum Theme {
    static let paper = Color(red: 0.953, green: 0.945, blue: 0.925)
    static let ink = Color(red: 0.11, green: 0.106, blue: 0.098)
    static let line = Color(red: 0.84, green: 0.82, blue: 0.79)
    static let muted = Color(red: 0.42, green: 0.41, blue: 0.38)
    static let tile = Color(red: 0.91, green: 0.90, blue: 0.87)
    static let warning = Color(red: 0.62, green: 0.32, blue: 0.10)
}

struct RGB: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    init(color: Color) {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(min(max(r, 0), 1)), Double(min(max(g, 0), 1)), Double(min(max(b, 0), 1)))
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    static let swatches: [RGB] = [
        RGB(1, 1, 1), RGB(0.96, 0.95, 0.92), RGB(0.91, 0.90, 0.88), RGB(0.82, 0.81, 0.79),
        RGB(0.60, 0.59, 0.57), RGB(0.12, 0.12, 0.11), RGB(0.91, 0.86, 0.77), RGB(0.80, 0.85, 0.80),
        RGB(0.82, 0.87, 0.91), RGB(0.92, 0.83, 0.80)
    ]
}

/// What goes behind the products.
enum BackdropChoice: Codable, Hashable {
    case surface(String)        // a photographic surface from the library (bundled or added)
    case colour(RGB)
    case transparent
}

/// The look applied to the whole batch.
struct Look: Codable, Hashable {
    var backdrop: BackdropChoice = .surface("dark_wood")
    var studioLight: Bool = false
    var shadow = ShadowParams()

    static let storageKey = "look.v3"
}

struct BatchItem: Identifiable, @unchecked Sendable {
    enum Status: Equatable {
        case processing
        case ready
        case check(String)      // cut out, but worth a look
        case failed(String)     // couldn't be cut out; kept as the original
    }

    let id: UUID
    var status: Status = .processing
    /// Use the cut-out version (false = keep the original photo untouched).
    var removed: Bool = true
    var edited: Bool = false
    var originalURL: URL
    var pixelSize: CGSize = .zero
    /// Full-resolution alpha matte (greyscale PNG).
    var alphaURL: URL?
    /// 1100 px versions for large previews.
    var previewPhotoURL: URL?
    var previewAlphaURL: URL?
    /// Small versions kept in memory for the grid.
    var gridPhoto: RGBAImage?
    var gridAlpha: [UInt8]?

    var canRemove: Bool { alphaURL != nil }
    var needsAttention: Bool {
        switch status { case .check, .failed: return true; default: return false }
    }
    var statusNote: String? {
        switch status {
        case .check(let s): return s
        case .failed(let s): return s
        default: return nil
        }
    }
}

struct EditTarget: Identifiable { let id: UUID }

/// Carries values that are safe to hand between threads here but aren't marked Sendable.
struct Box<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
