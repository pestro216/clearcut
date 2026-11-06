import Foundation
import CoreGraphics

/// What goes behind the item.
public enum BackdropSource {
    case transparent
    case colour(r: Float, g: Float, b: Float, studioLight: Bool)
    case image(CGImage)
}

/// Puts the cut-out item onto a backdrop with its shadow, at the photo's full resolution.
/// Blending happens in linear light so edges and shadows darken the surface the way real light does.
public enum Compositor {

    public static func render(photo: RGBAImage, alpha: [UInt8], backdrop: BackdropSource, shadow: ShadowParams) -> RGBAImage {
        render(foreground: Matting.foreground(full: photo, alpha: alpha), alpha: alpha, backdrop: backdrop, shadow: shadow)
    }

    /// Same, with the item's edge colours already worked out (they don't depend on the look,
    /// so previews keep them and only redo the backdrop and shadow when the look changes).
    public static func render(foreground fg: RGBAImage, alpha: [UInt8], backdrop: BackdropSource, shadow: ShadowParams) -> RGBAImage {
        let w = fg.width, h = fg.height
        if case .transparent = backdrop {
            var out = fg
            for i in 0..<(w * h) { out.pixels[i * 4 + 3] = alpha[i] }
            return out
        }
        var bg = backdropImage(backdrop, width: w, height: h)
        if let s = ShadowModel.density(alpha: alpha, width: w, height: h, params: shadow) {
            applyShadow(&bg, density: s)
        }
        overInPlace(fg: fg, alpha: alpha, bg: &bg)
        return bg
    }

    /// The backdrop at exactly w x h: images fill the frame (centred crop), never distorted.
    public static func backdropImage(_ source: BackdropSource, width w: Int, height h: Int) -> RGBAImage {
        switch source {
        case .transparent:
            return RGBAImage(width: w, height: h, fill: (255, 255, 255))
        case .colour(let r, let g, let b, let studio):
            var img = RGBAImage(width: w, height: h, fill: (UInt8(min(255, max(0, r * 255))), UInt8(min(255, max(0, g * 255))), UInt8(min(255, max(0, b * 255)))))
            if studio { studioLight(&img) }
            return img
        case .image(let cg):
            let k = max(Double(w) / Double(cg.width), Double(h) / Double(cg.height))
            let dw = Double(cg.width) * k, dh = Double(cg.height) * k
            var p = [UInt8](repeating: 255, count: w * h * 4)
            p.withUnsafeMutableBytes { raw in
                if let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                       space: ColourSpaces.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.interpolationQuality = .high
                    ctx.draw(cg, in: CGRect(x: (Double(w) - dw) / 2, y: (Double(h) - dh) / 2, width: dw, height: dh))
                }
            }
            return RGBAImage(width: w, height: h, pixels: p)
        }
    }

    /// A gentle overhead-softbox falloff for plain colours: brighter centre, slightly darker corners.
    static func studioLight(_ img: inout RGBAImage) {
        let w = img.width, h = img.height
        let cx = Float(w) / 2, cy = Float(h) * 0.45
        let r = Float(max(w, h)) * 0.75
        for y in 0..<h {
            for x in 0..<w {
                let d = sqrt((Float(x) - cx) * (Float(x) - cx) + (Float(y) - cy) * (Float(y) - cy)) / r
                let gain = 1.04 - 0.12 * min(1, d * d)
                let i = (y * w + x) * 4
                // Ordered dither so the gentle falloff doesn't band in 8-bit output.
                let dither = (Float((x * 7 + y * 13) & 15) / 16 - 0.5) / 255
                for c in 0..<3 {
                    let lin = Linear.toLinear[Int(img.pixels[i + c])] * gain
                    let enc = (lin <= 0.0031308 ? lin * 12.92 : 1.055 * pow(lin, 1 / 2.4) - 0.055) + dither
                    img.pixels[i + c] = UInt8(max(0, min(255, enc * 255 + 0.5)))
                }
            }
        }
    }

    /// Multiplies the surface by the light that reaches it.
    static func applyShadow(_ bg: inout RGBAImage, density s: [UInt8]) {
        let n = bg.width * bg.height
        bg.pixels.withUnsafeMutableBufferPointer { p in
            for i in 0..<n {
                let d = s[i]
                if d == 0 { continue }
                let keep = 1 - Float(d) / 255
                for c in 0..<3 {
                    p[i * 4 + c] = Linear.toSRGB(Linear.toLinear[Int(p[i * 4 + c])] * keep)
                }
            }
        }
    }

    /// Item over backdrop, blended in linear light.
    static func overInPlace(fg: RGBAImage, alpha: [UInt8], bg: inout RGBAImage) {
        let n = bg.width * bg.height
        bg.pixels.withUnsafeMutableBufferPointer { o in
            fg.pixels.withUnsafeBufferPointer { f in
                for i in 0..<n {
                    let a = alpha[i]
                    if a == 0 { continue }
                    if a == 255 {
                        o[i * 4] = f[i * 4]; o[i * 4 + 1] = f[i * 4 + 1]; o[i * 4 + 2] = f[i * 4 + 2]
                        continue
                    }
                    let af = Float(a) / 255
                    for c in 0..<3 {
                        let v = Linear.toLinear[Int(f[i * 4 + c])] * af + Linear.toLinear[Int(o[i * 4 + c])] * (1 - af)
                        o[i * 4 + c] = Linear.toSRGB(v)
                    }
                }
            }
        }
    }
}

/// sRGB transfer function lookups.
public enum Linear {
    public static let toLinear: [Float] = (0..<256).map { v in
        let c = Float(v) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    static let encode: [UInt8] = (0..<4096).map { i in
        let l = Float(i) / 4095
        let c = l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, c * 255 + 0.5)))
    }
    @inline(__always) public static func toSRGB(_ l: Float) -> UInt8 {
        let i = Int(max(0, min(1, l)) * 4095 + 0.5)
        return encode[i]
    }
}
