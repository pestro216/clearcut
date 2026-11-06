import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// All compositing happens in Core Image, in a bottom-left origin coordinate space of the output size.
enum Renderer {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .cacheIntermediates: false
    ])

    struct Placement {
        var offset: CGSize
        var scale: CGFloat
    }

    static func canvasSize(look: Look, originalSize: CGSize, longSide: CGFloat) -> CGSize {
        let ratio = look.shape.ratio ?? (originalSize.width / max(originalSize.height, 1))
        if ratio >= 1 {
            return CGSize(width: longSide, height: max(1, (longSide / ratio).rounded()))
        }
        return CGSize(width: max(1, (longSide * ratio).rounded()), height: longSide)
    }

    static func cgImage(_ image: CIImage, size: CGSize) -> CGImage? {
        context.createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: sRGB)
    }

    // MARK: Full composition

    static func compose(cutout: CIImage, look: Look, place: Placement, photo: CIImage?, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        let fg = layer(cutout: cutout, look: look, place: place, size: size)
        let bg = backdrop(look, photo: photo, size: size)
        return fg.composited(over: bg).cropped(to: rect)
    }

    /// The item with its shadow, on a transparent canvas.
    static func layer(cutout: CIImage, look: Look, place: Placement, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        let ce = cutout.extent
        guard ce.width > 0, ce.height > 0 else { return CIImage.empty() }
        let fit = min(size.width / ce.width, size.height / ce.height) * CGFloat(look.itemSize) * place.scale
        let iw = ce.width * fit, ih = ce.height * fit
        let cx = (0.5 + place.offset.width) * size.width
        let cyFromTop = (0.5 + place.offset.height) * size.height
        let x = cx - iw / 2
        let groundY = size.height - cyFromTop - ih / 2
        let lift: CGFloat = look.shadow == .floating ? ih * 0.06 : 0

        let grounded = cutout
            .transformed(by: CGAffineTransform(translationX: -ce.minX, y: -ce.minY))
            .transformed(by: CGAffineTransform(scaleX: fit, y: fit))
            .transformed(by: CGAffineTransform(translationX: x, y: groundY))
        let item = grounded.transformed(by: CGAffineTransform(translationX: 0, y: lift))

        var out = item
        if let shadow = shadowImage(item: grounded, style: look.shadow, strength: CGFloat(look.shadowStrength),
                                    base: groundY, cx: cx, iw: iw, ih: ih) {
            out = item.composited(over: shadow)
        }
        return out.cropped(to: rect)
    }

    // MARK: Shadows

    static func silhouette(_ image: CIImage, alpha: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }

    /// Squashes an image towards a ground line, optionally narrowing it around cx.
    static func flatten(_ image: CIImage, base: CGFloat, factor: CGFloat, widthFactor: CGFloat, cx: CGFloat) -> CIImage {
        let t = CGAffineTransform(translationX: -cx, y: -base)
            .concatenating(CGAffineTransform(scaleX: widthFactor, y: factor))
            .concatenating(CGAffineTransform(translationX: cx, y: base))
        return image.transformed(by: t)
    }

    static func shadowImage(item: CIImage, style: ShadowStyle, strength: CGFloat,
                            base: CGFloat, cx: CGFloat, iw: CGFloat, ih: CGFloat) -> CIImage? {
        let a = max(0, min(1, strength))
        let m = max(iw, ih)
        let sil = silhouette(item, alpha: 1)
        switch style {
        case .none:
            return nil
        case .soft:
            let contact = silhouette(flatten(sil, base: base - ih * 0.004, factor: 0.035, widthFactor: 0.96, cx: cx), alpha: 0.85 * a)
                .applyingGaussianBlur(sigma: Double(m * 0.008))
            let spread = silhouette(flatten(sil, base: base - ih * 0.01, factor: 0.10, widthFactor: 1.05, cx: cx), alpha: 0.45 * a)
                .applyingGaussianBlur(sigma: Double(m * 0.035))
            return contact.composited(over: spread)
        case .floating:
            return silhouette(flatten(sil, base: base - ih * 0.02, factor: 0.07, widthFactor: 0.82, cx: cx), alpha: 0.55 * a)
                .applyingGaussianBlur(sigma: Double(m * 0.04))
        case .hard:
            let k: CGFloat = 0.7, squash: CGFloat = 0.42
            let t = CGAffineTransform(a: 1, b: 0, c: k, d: squash, tx: -k * base, ty: base - squash * base)
            let cast = silhouette(sil.transformed(by: t), alpha: 0.5 * a)
                .applyingGaussianBlur(sigma: Double(m * 0.006))
            let contact = silhouette(flatten(sil, base: base, factor: 0.03, widthFactor: 0.95, cx: cx), alpha: 0.7 * a)
                .applyingGaussianBlur(sigma: Double(m * 0.006))
            return contact.composited(over: cast)
        }
    }

    // MARK: Backdrops

    static func backdrop(_ look: Look, photo: CIImage?, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        switch look.backdrop {
        case .transparent:
            return CIImage.empty()
        case .colour(let c):
            var base = CIImage(color: c.ciColor).cropped(to: rect)
            if look.studioLight { base = studio(base, size: size) }
            return base
        case .texture(let kind):
            return texture(kind, size: size)
        case .photo:
            if let photo { return aspectFill(photo, size: size).cropped(to: rect) }
            return CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: rect)
        }
    }

    static func studio(_ image: CIImage, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        let m = max(size.width, size.height)
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.6)

        let light = CIFilter.radialGradient()
        light.center = centre
        light.radius0 = 0
        light.radius1 = Float(m * 0.7)
        light.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 0.22)
        light.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)

        let vignette = CIFilter.radialGradient()
        vignette.center = centre
        vignette.radius0 = Float(m * 0.35)
        vignette.radius1 = Float(m * 0.95)
        vignette.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        vignette.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0.13)

        guard let l = light.outputImage, let v = vignette.outputImage else { return image }
        return v.cropped(to: rect).composited(over: l.cropped(to: rect).composited(over: image))
    }

    static func aspectFill(_ image: CIImage, size: CGSize) -> CIImage {
        let e = image.extent
        let k = max(size.width / e.width, size.height / e.height)
        let dx = (size.width - e.width * k) / 2, dy = (size.height - e.height * k) / 2
        return image
            .transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: k, y: k))
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
    }

    static func texture(_ kind: TextureKind, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        let s = max(size.width, size.height) / 1000

        func noise(_ sx: CGFloat, _ sy: CGFloat, blur: CGFloat, contrast: Float) -> CIImage {
            guard let random = CIFilter.randomGenerator().outputImage else { return CIImage.empty() }
            let opaque = random.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
            let mono = CIFilter.colorControls()
            mono.inputImage = opaque.transformed(by: CGAffineTransform(scaleX: sx * s, y: sy * s))
            mono.saturation = 0
            mono.contrast = contrast
            var out = mono.outputImage ?? CIImage.empty()
            if blur > 0 { out = out.applyingGaussianBlur(sigma: Double(blur * s)) }
            return out.cropped(to: rect)
        }
        func blend(_ top: CIImage, over base: CIImage) -> CIImage {
            let f = CIFilter.softLightBlendMode()
            f.inputImage = top
            f.backgroundImage = base
            return (f.outputImage ?? base).cropped(to: rect)
        }
        func colour(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
            CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: rect)
        }

        switch kind {
        case .paper:
            return blend(noise(1.5, 1.5, blur: 0.6, contrast: 0.35), over: colour(0.95, 0.94, 0.91))
        case .plaster:
            var b = colour(0.89, 0.86, 0.81)
            b = blend(noise(40, 40, blur: 30, contrast: 1.0), over: b)
            return blend(noise(1.5, 1.5, blur: 0.8, contrast: 0.5), over: b)
        case .concrete:
            var b = colour(0.63, 0.62, 0.60)
            b = blend(noise(60, 60, blur: 40, contrast: 1.4), over: b)
            return blend(noise(2, 2, blur: 0.7, contrast: 0.9), over: b)
        case .slate:
            var b = colour(0.24, 0.26, 0.28)
            b = blend(noise(50, 50, blur: 30, contrast: 1.0), over: b)
            return blend(noise(1.5, 1.5, blur: 0.7, contrast: 0.8), over: b)
        case .sand:
            var b = colour(0.86, 0.79, 0.67)
            b = blend(noise(30, 30, blur: 25, contrast: 0.6), over: b)
            return blend(noise(1.2, 1.2, blur: 0.5, contrast: 1.2), over: b)
        case .oak:
            var b = colour(0.70, 0.53, 0.36)
            b = blend(noise(300, 1.2, blur: 1.2, contrast: 1.3), over: b)
            return blend(noise(900, 6, blur: 3, contrast: 1.0), over: b)
        case .walnut:
            var b = colour(0.36, 0.24, 0.16)
            b = blend(noise(300, 1.2, blur: 1.2, contrast: 1.4), over: b)
            return blend(noise(900, 6, blur: 3, contrast: 1.1), over: b)
        }
    }

    static let textureThumbs: [TextureKind: UIImage] = {
        var out: [TextureKind: UIImage] = [:]
        let size = CGSize(width: 600, height: 600)
        for k in TextureKind.allCases {
            if let cg = Renderer.cgImage(Renderer.texture(k, size: size), size: size), let small = ImageFiles.scaled(cg, maxSide: 180) {
                out[k] = UIImage(cgImage: small)
            }
        }
        return out
    }()
}
