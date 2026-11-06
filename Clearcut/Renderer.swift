import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// All compositing happens in Core Image, in a bottom-left origin space the size of the photo.
/// The photo is never moved, cropped or resized: the item stays exactly where it was shot.
enum Renderer {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .cacheIntermediates: false
    ])

    static func cgImage(_ image: CIImage, size: CGSize) -> CGImage? {
        context.createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: sRGB)
    }

    /// Loads a greyscale mask without colour management so its values stay exact.
    static func maskImage(_ cg: CGImage) -> CIImage {
        CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
    }

    static func maskImage(url: URL) -> CIImage? {
        CIImage(contentsOf: url, options: [.colorSpace: NSNull()])
    }

    /// Scales an image so its extent is exactly `size` at the origin.
    static func fitted(_ image: CIImage, to size: CGSize) -> CIImage {
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return image }
        return image
            .transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: size.width / e.width, y: size.height / e.height))
    }

    // MARK: Composition

    static func compose(original: CIImage, mask: CIImage, bbox: CGRect, look: Look, photo: CIImage?, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        let o = fitted(original, to: size).cropped(to: rect)
        let m = fitted(mask, to: size).cropped(to: rect)
        let item = cutout(original: o, mask: m, size: size)
        var below = backdrop(look, photo: photo, size: size)
        if let shadow = shadowImage(mask: m, bbox: bbox, look: look, size: size) {
            below = shadow.composited(over: below)
        }
        return item.composited(over: below).cropped(to: rect)
    }

    /// The item on transparency, with edge colours cleaned of the old background.
    static func cutout(original: CIImage, mask: CIImage, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        let long = max(size.width, size.height)
        let choke = max(1.0, long / 1600)

        // Pixels safely inside the item.
        let inner = mask
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: choke])
            .cropped(to: rect)
        let innerColour = original.applyingFilter("CIBlendWithRedMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: inner
        ])
        // Spread the item's own colours outwards so edge pixels don't carry the old background's tint.
        let spread = innerColour
            .applyingGaussianBlur(sigma: Double(choke * 2.5))
            .cropped(to: rect)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        let colour = original.applyingFilter("CIBlendWithRedMask", parameters: [
            kCIInputBackgroundImageKey: spread,
            kCIInputMaskImageKey: inner
        ])
        return colour.applyingFilter("CIBlendWithRedMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask
        ]).cropped(to: rect)
    }

    // MARK: Shadows

    /// Black, with alpha taken from the mask's red channel times `alpha`.
    static func silhouette(_ mask: CIImage, alpha: CGFloat) -> CIImage {
        mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: alpha, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }

    static func fade(_ image: CIImage, by alpha: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
        ])
    }

    static func flatten(_ image: CIImage, base: CGFloat, factor: CGFloat, widthFactor: CGFloat, cx: CGFloat) -> CIImage {
        let t = CGAffineTransform(translationX: -cx, y: -base)
            .concatenating(CGAffineTransform(scaleX: widthFactor, y: factor))
            .concatenating(CGAffineTransform(translationX: cx, y: base))
        return image.transformed(by: t)
    }

    static func shadowImage(mask: CIImage, bbox: CGRect, look: Look, size: CGSize) -> CIImage? {
        let rect = CGRect(origin: .zero, size: size)
        let a = CGFloat(max(0, min(1, look.shadowStrength)))
        let soft = CGFloat(max(0, min(1, look.shadowSoftness)))
        let dist = CGFloat(max(0, min(1, look.shadowDistance)))
        let long = max(size.width, size.height)
        let angle = CGFloat(look.shadowAngle) * .pi / 180
        // Screen direction (y down) converted to Core Image's y-up space.
        let dir = CGVector(dx: cos(angle), dy: -sin(angle))

        let iw = bbox.width * size.width, ih = bbox.height * size.height
        let cx = (bbox.midX) * size.width
        let base = (1 - bbox.maxY) * size.height
        let m = max(iw, ih, 1)
        let sil = silhouette(mask, alpha: 1)

        let shadow: CIImage?
        switch look.shadow {
        case .none:
            shadow = nil
        case .drop:
            // Light from above, item lying flat: a tight, offset copy of its outline.
            let off = (0.002 + dist * 0.03) * long
            let blur = 0.5 + soft * long * 0.012
            shadow = fade(sil.transformed(by: CGAffineTransform(translationX: dir.dx * off, y: dir.dy * off))
                            .applyingGaussianBlur(sigma: Double(blur)), by: 0.8 * a)
        case .floating:
            // Item hovering above the surface: further away, much softer and lighter.
            let off = (0.015 + dist * 0.05) * long
            let blur = long * (0.01 + soft * 0.03)
            shadow = fade(sil.transformed(by: CGAffineTransform(translationX: dir.dx * off, y: dir.dy * off))
                            .applyingGaussianBlur(sigma: Double(blur)), by: 0.55 * a)
        case .soft:
            // Product standing on a surface: contact shadow under its base.
            let contact = fade(flatten(sil, base: base - ih * 0.004, factor: 0.035, widthFactor: 0.96, cx: cx)
                                .applyingGaussianBlur(sigma: Double(m * (0.004 + soft * 0.008))), by: 0.85 * a)
            let spread = fade(flatten(sil, base: base - ih * 0.01, factor: 0.10, widthFactor: 1.05, cx: cx)
                                .applyingGaussianBlur(sigma: Double(m * (0.02 + soft * 0.03))), by: 0.45 * a)
            shadow = contact.composited(over: spread)
        case .hard:
            // Low sun: the outline cast across the surface behind the product.
            let k = dir.dx * 0.9, squash: CGFloat = 0.42
            let t = CGAffineTransform(a: 1, b: 0, c: k, d: squash, tx: -k * base, ty: base - squash * base)
            let cast = fade(sil.transformed(by: t).applyingGaussianBlur(sigma: Double(1 + soft * m * 0.02)), by: 0.55 * a)
            let contact = fade(flatten(sil, base: base, factor: 0.03, widthFactor: 0.95, cx: cx)
                                .applyingGaussianBlur(sigma: Double(1 + m * 0.005)), by: 0.7 * a)
            shadow = contact.composited(over: cast)
        }
        return shadow?.cropped(to: rect)
    }

    // MARK: Backdrops

    private static var surfaceCache: [String: CIImage] = [:]
    private static let cacheLock = NSLock()

    static func surfaceImage(_ id: String) -> CIImage? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let c = surfaceCache[id] { return c }
        guard let url = Bundle.main.url(forResource: id, withExtension: "jpg"),
              let img = CIImage(contentsOf: url) else { return nil }
        surfaceCache[id] = img
        return img
    }

    static func surfaceThumb(_ id: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: "thumb-\(id)", withExtension: "jpg") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func backdrop(_ look: Look, photo: CIImage?, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        switch look.backdrop {
        case .transparent:
            return CIImage.empty()
        case .colour(let c):
            var base = CIImage(color: c.ciColor).cropped(to: rect)
            if look.studioLight { base = studio(base, size: size) }
            return base
        case .surface(let id):
            if let img = surfaceImage(id) { return aspectFill(img, size: size).cropped(to: rect) }
            return CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: rect)
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
}
