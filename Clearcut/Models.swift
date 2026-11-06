import SwiftUI
import UIKit
import CoreImage

enum Theme {
    static let paper = Color(red: 0.953, green: 0.945, blue: 0.925)
    static let ink = Color(red: 0.11, green: 0.106, blue: 0.098)
    static let line = Color(red: 0.84, green: 0.82, blue: 0.79)
    static let muted = Color(red: 0.42, green: 0.41, blue: 0.38)
}

struct RGB: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(color: Color) {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(min(max(r, 0), 1)), Double(min(max(g, 0), 1)), Double(min(max(b, 0), 1)))
    }

    var color: Color { Color(red: r, green: g, blue: b) }
    var ciColor: CIColor { CIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b)) }

    static let swatches: [RGB] = [
        RGB(1, 1, 1), RGB(0.96, 0.95, 0.92), RGB(0.91, 0.90, 0.88), RGB(0.82, 0.81, 0.79),
        RGB(0.60, 0.59, 0.57), RGB(0.12, 0.12, 0.11), RGB(0.91, 0.86, 0.77), RGB(0.80, 0.85, 0.80),
        RGB(0.82, 0.87, 0.91), RGB(0.92, 0.83, 0.80), RGB(0.77, 0.33, 0.24), RGB(0.18, 0.36, 0.31),
        RGB(0.17, 0.23, 0.34)
    ]
}

enum TextureKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case paper, plaster, concrete, slate, sand, oak, walnut
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum Backdrop: Codable, Hashable {
    case transparent
    case colour(RGB)
    case texture(TextureKind)
    case photo
}

enum ShadowStyle: String, CaseIterable, Identifiable, Codable, Hashable {
    case none, soft, floating, hard
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CanvasShape: String, CaseIterable, Identifiable, Codable, Hashable {
    case original, square, portrait, tall, story, landscape
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return "Original"
        case .square: return "Square"
        case .portrait: return "4:5"
        case .tall: return "3:4"
        case .story: return "9:16"
        case .landscape: return "4:3"
        }
    }
    /// width divided by height; nil means use the photo's own shape
    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .portrait: return 4.0 / 5.0
        case .tall: return 3.0 / 4.0
        case .story: return 9.0 / 16.0
        case .landscape: return 4.0 / 3.0
        }
    }
}

struct Look: Codable, Hashable {
    var backdrop: Backdrop = .colour(RGB(1, 1, 1))
    var studioLight: Bool = true
    var shadow: ShadowStyle = .soft
    var shadowStrength: Double = 0.6
    var shape: CanvasShape = .square
    var itemSize: Double = 0.78
    var exportLongSide: Int = 2048
    var preferPNG: Bool = false
}

struct BatchItem: Identifiable, @unchecked Sendable {
    enum Status { case ready, noSubject }

    let id: UUID
    var status: Status = .ready
    var removed: Bool = true
    var offset: CGSize = .zero
    var scale: CGFloat = 1
    var originalURL: URL
    var originalSize: CGSize
    var cutoutURL: URL?
    var smallOriginal: CGImage?
    var smallCutout: CGImage?

    var canRemove: Bool { cutoutURL != nil }
}

struct EditTarget: Identifiable {
    let id: UUID
}

/// Carries values that are safe to hand between threads here but aren't marked Sendable.
struct Box<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
