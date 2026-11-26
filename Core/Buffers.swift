import Foundation
import CoreGraphics
import Accelerate
import ImageIO
import UniformTypeIdentifiers

/// 8-bit RGBA pixels, rows top to bottom, colour not premultiplied (photos are opaque).
public struct RGBAImage {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width; self.height = height; self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: (UInt8, UInt8, UInt8)) {
        self.width = width; self.height = height
        var p = [UInt8](repeating: 255, count: width * height * 4)
        p.withUnsafeMutableBufferPointer { b in
            var i = 0
            while i < b.count { b[i] = fill.0; b[i + 1] = fill.1; b[i + 2] = fill.2; i += 4 }
        }
        pixels = p
    }

    /// Draws any CGImage into sRGB RGBA at the given size (default: its own size).
    public init?(cgImage: CGImage, width: Int? = nil, height: Int? = nil) {
        let w = width ?? cgImage.width, h = height ?? cgImage.height
        guard w > 0, h > 0 else { return nil }
        var p = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = p.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: ColourSpaces.sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.width = w; self.height = h; self.pixels = p
    }

    /// Opaque CGImage (alpha ignored).
    public func makeOpaqueCGImage() -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: ColourSpaces.sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// CGImage with straight (non-premultiplied) alpha, for transparent PNG export.
    public func makeAlphaCGImage() -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: ColourSpaces.sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Area-averaged downscale (or bilinear upscale) through Core Graphics.
    public func resized(width w: Int, height h: Int) -> RGBAImage {
        guard let cg = makeOpaqueCGImage(), let r = RGBAImage(cgImage: cg, width: w, height: h) else { return self }
        return r
    }

    /// One channel in linear light (0...1), for physically meaningful mixing.
    public func linearChannel(_ c: Int) -> Plane {
        var out = [Float](repeating: 0, count: width * height)
        let lut = Linear.toLinear
        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for i in 0..<(width * height) { dst[i] = lut[Int(src[i * 4 + c])] }
            }
        }
        return Plane(width: width, height: height, data: out)
    }

    /// One channel (0 red, 1 green, 2 blue) as floats 0...1.
    public func channel(_ c: Int) -> Plane {
        var out = [Float](repeating: 0, count: width * height)
        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let n = width * height
                for i in 0..<n { dst[i] = Float(src[i * 4 + c]) * (1.0 / 255.0) }
            }
        }
        return Plane(width: width, height: height, data: out)
    }
}

/// A single-channel float image.
public struct Plane {
    public var width: Int
    public var height: Int
    public var data: [Float]

    public init(width: Int, height: Int, data: [Float]) {
        self.width = width; self.height = height; self.data = data
    }

    public init(width: Int, height: Int, value: Float = 0) {
        self.width = width; self.height = height
        data = [Float](repeating: value, count: width * height)
    }

    public init(bytes: [UInt8], width: Int, height: Int) {
        self.width = width; self.height = height
        var d = [Float](repeating: 0, count: bytes.count)
        bytes.withUnsafeBufferPointer { s in
            d.withUnsafeMutableBufferPointer { o in
                for i in 0..<s.count { o[i] = Float(s[i]) * (1.0 / 255.0) }
            }
        }
        data = d
    }

    public var count: Int { width * height }

    public func toBytes() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        data.withUnsafeBufferPointer { s in
            out.withUnsafeMutableBufferPointer { o in
                for i in 0..<s.count {
                    let v = s[i] * 255 + 0.5
                    o[i] = v <= 0 ? 0 : (v >= 255 ? 255 : UInt8(v))
                }
            }
        }
        return out
    }

    /// Resample with vImage (Lanczos for downscale, bilinear-quality for upscale).
    public func resized(width w: Int, height h: Int) -> Plane {
        if w == width && h == height { return self }
        var out = [Float](repeating: 0, count: w * h)
        var src = data
        src.withUnsafeMutableBytes { s in
            out.withUnsafeMutableBytes { d in
                var sb = vImage_Buffer(data: s.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
                var db = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
                _ = vImageScale_PlanarF(&sb, &db, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        return Plane(width: w, height: h, data: out)
    }

    /// Box filter of the given radius (window 2r+1), edges extended. Running sums, O(n) per pass.
    public func boxBlurred(radius r: Int) -> Plane {
        guard r > 0, width > 0, height > 0 else { return self }
        let w = width, h = height
        let norm = 1 / Float(2 * r + 1)
        var tmp = [Float](repeating: 0, count: count)
        var out = [Float](repeating: 0, count: count)
        data.withUnsafeBufferPointer { src in
            tmp.withUnsafeMutableBufferPointer { t in
                for y in 0..<h {
                    let row = y * w
                    var acc: Float = 0
                    for k in -r...r { acc += src[row + min(w - 1, max(0, k))] }
                    for x in 0..<w {
                        t[row + x] = acc * norm
                        acc += src[row + min(w - 1, x + r + 1)] - src[row + max(0, x - r)]
                    }
                }
            }
        }
        tmp.withUnsafeBufferPointer { t in
            out.withUnsafeMutableBufferPointer { o in
                var acc = [Float](repeating: 0, count: w)
                for k in -r...r {
                    let row = min(h - 1, max(0, k)) * w
                    for x in 0..<w { acc[x] += t[row + x] }
                }
                for y in 0..<h {
                    let row = y * w
                    let addRow = min(h - 1, y + r + 1) * w, subRow = max(0, y - r) * w
                    for x in 0..<w {
                        o[row + x] = acc[x] * norm
                        acc[x] += t[addRow + x] - t[subRow + x]
                    }
                }
            }
        }
        return Plane(width: w, height: h, data: out)
    }

    /// Gaussian approximated by three box passes.
    public func gaussianBlurred(sigma: Float) -> Plane {
        guard sigma >= 0.5 else { return self }
        let w = sqrt(4 * sigma * sigma + 1)
        let r = max(1, Int((w - 1) / 2 + 0.5))
        return boxBlurred(radius: r).boxBlurred(radius: r).boxBlurred(radius: r)
    }

    @inline(__always) public func at(_ x: Int, _ y: Int) -> Float { data[y * width + x] }

    /// Bilinear sample at continuous coordinates (pixel centres at integer + 0.5).
    @inline(__always) public func sample(_ fx: Float, _ fy: Float) -> Float {
        let x = max(0, min(max(0, Float(width) - 1.001), fx - 0.5))
        let y = max(0, min(max(0, Float(height) - 1.001), fy - 0.5))
        let x0 = Int(x), y0 = Int(y)
        let tx = x - Float(x0), ty = y - Float(y0)
        let i = y0 * width + x0
        let dx = x0 + 1 < width ? 1 : 0, dy = y0 + 1 < height ? width : 0
        let a = data[i], b = data[i + dx], c = data[i + dy], d = data[i + dy + dx]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    }

    public func map(_ f: (Float) -> Float) -> Plane {
        Plane(width: width, height: height, data: data.map(f))
    }

    public static func combine(_ a: Plane, _ b: Plane, _ f: (Float, Float) -> Float) -> Plane {
        var out = [Float](repeating: 0, count: a.count)
        a.data.withUnsafeBufferPointer { pa in
            b.data.withUnsafeBufferPointer { pb in
                out.withUnsafeMutableBufferPointer { o in
                    for i in 0..<o.count { o[i] = f(pa[i], pb[i]) }
                }
            }
        }
        return Plane(width: a.width, height: a.height, data: out)
    }

    public static func * (a: Plane, b: Plane) -> Plane {
        var out = [Float](repeating: 0, count: a.count)
        vDSP_vmul(a.data, 1, b.data, 1, &out, 1, vDSP_Length(a.count))
        return Plane(width: a.width, height: a.height, data: out)
    }

    public var mean: Float {
        var m: Float = 0
        vDSP_meanv(data, 1, &m, vDSP_Length(count))
        return m
    }
}

public enum ColourSpaces {
    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    public static let gray = CGColorSpaceCreateDeviceGray()
}

public enum ImageIOHelpers {
    /// The longest side any photo is worked on at. Every iPhone photo (up to 48 MP, 8064 px) fits;
    /// a panorama or a very large file is scaled down, so one image can't exhaust the phone's memory.
    public static let maxSide = 8192

    /// Decodes with EXIF orientation applied, at full size (up to `maxSide`) unless maxPixel is smaller.
    public static func loadOriented(_ data: Data, maxPixel: Int? = nil) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let full = min(maxSide, orientedSize(data).map { Int(max($0.width, $0.height)) } ?? maxSide)
        guard full > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixel ?? full, full),
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    /// Pixel size after orientation, without decoding.
    public static func orientedSize(_ data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    public static func encode(_ cg: CGImage, type: UTType, quality: CGFloat = 0.95) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    public static func grayImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: ColourSpaces.gray, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Reads a greyscale image back into bytes, resampled to the given size if needed.
    public static func grayBytes(_ cg: CGImage, width: Int? = nil, height: Int? = nil) -> [UInt8] {
        let w = width ?? cg.width, h = height ?? cg.height
        var bytes = [UInt8](repeating: 0, count: w * h)
        bytes.withUnsafeMutableBytes { raw in
            if let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                   space: ColourSpaces.gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                ctx.interpolationQuality = .high
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        return bytes
    }
}
