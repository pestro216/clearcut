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

/// A photographic surface bundled with the app (Clearcut/Backdrops/<id>.jpg).
struct Surface: Identifiable, Hashable {
    let id: String
    let title: String

    enum Group: String, CaseIterable, Identifiable {
        case studio = "Studio", wood = "Wood", marble = "Marble", stone = "Stone", fabric = "Fabric and paper"
        var id: String { rawValue }
    }

    static let catalogue: [Group: [Surface]] = [
        .studio: [
            Surface(id: "studio-white", title: "White"), Surface(id: "studio-warm", title: "Warm"),
            Surface(id: "studio-grey", title: "Grey"), Surface(id: "studio-blush", title: "Blush"),
            Surface(id: "studio-sage", title: "Sage")
        ],
        .wood: [
            Surface(id: "wood-cherry", title: "Cherry"), Surface(id: "wood-oak", title: "Oak"),
            Surface(id: "wood-walnut", title: "Walnut"), Surface(id: "wood-whitewash", title: "Whitewash")
        ],
        .marble: [
            Surface(id: "marble-white", title: "White"), Surface(id: "marble-warm", title: "Warm"),
            Surface(id: "marble-black", title: "Black")
        ],
        .stone: [
            Surface(id: "concrete-light", title: "Concrete"), Surface(id: "concrete-dark", title: "Dark concrete"),
            Surface(id: "plaster", title: "Plaster"), Surface(id: "terrazzo", title: "Terrazzo")
        ],
        .fabric: [
            Surface(id: "linen", title: "Linen"), Surface(id: "linen-grey", title: "Grey linen"),
            Surface(id: "paper-kraft", title: "Kraft paper")
        ]
    ]

    static func group(of id: String) -> Group? {
        catalogue.first { $0.value.contains { $0.id == id } }?.key
    }
}

enum Backdrop: Codable, Hashable {
    case transparent
    case colour(RGB)
    case surface(String)
    case photo
}

enum ShadowStyle: String, CaseIterable, Identifiable, Codable, Hashable {
    case none, drop, soft, floating, hard
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var usesDistance: Bool { self == .drop || self == .floating }
    var usesDirection: Bool { self == .drop || self == .floating || self == .hard }
}

struct Look: Codable, Hashable {
    var backdrop: Backdrop = .surface("wood-cherry")
    var studioLight: Bool = false
    var shadow: ShadowStyle = .drop
    var shadowStrength: Double = 0.55
    var shadowSoftness: Double = 0.5
    var shadowDistance: Double = 0.35
    /// Direction the shadow falls, in degrees: 0 right, 90 down, 180 left, 270 up.
    var shadowAngle: Double = 120

    static let storageKey = "look.v2"
}

struct BatchItem: Identifiable, @unchecked Sendable {
    enum Status { case ready, noSubject }

    let id: UUID
    var status: Status = .ready
    var removed: Bool = true
    var originalURL: URL
    var pixelSize: CGSize
    var maskURL: URL?
    /// Bounding box of the item, normalised, top-left origin.
    var bbox: CGRect = .zero
    var smallOriginal: CGImage?
    var smallMask: CGImage?

    var canRemove: Bool { maskURL != nil }
}

struct EditTarget: Identifiable {
    let id: UUID
}

/// Carries values that are safe to hand between threads here but aren't marked Sendable.
struct Box<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
