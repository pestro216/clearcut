import Foundation
import CoreGraphics
import CoreML

/// BiRefNet Lite (Zheng et al., "Bilateral Reference for High-Resolution Dichotomous Image
/// Segmentation", 2024; MIT licence), converted to Core ML by the birefnet-lite-coreml project
/// (MIT). A network trained specifically to separate an object from its background with accurate,
/// soft edges, unlike Apple's general subject finder, which predicts on a coarse grid.
///
/// Contract of the converted model: input `image`, Float32 1x3x1024x1024, RGB 0...1 normalised
/// with the ImageNet mean and deviation; output `mask_logits`, Float32 1x1x1024x1024, logits.
///
/// Speed. The conversion recommends the CPU, because reduced-precision hardware can change the
/// result. The CPU is also the slowest place to run it. In the app (`accelerate`), the phone's
/// GPU is tried, but only trusted after it has been checked: the first photo runs on both, and
/// the GPU is used from then on only if the two agree (same outline, near-identical values).
/// The verdict is remembered per iOS version. Any later GPU output that is not sane (NaN, flat)
/// falls back to the CPU for good. The test bench stays on the CPU, so its numbers are stable.
public final class CutoutNetwork: @unchecked Sendable {
    public static let side = 1024
    private let compiledURL: URL
    private let accelerate: Bool
    private var cpuModel: MLModel?
    private var gpuModel: MLModel?
    private var inputName = "image"
    private var outputName = "mask_logits"
    private let lock = NSLock()
    /// Range and mean of the last raw output, for the quality report.
    public private(set) var lastOutputRange: (min: Float, max: Float, mean: Float) = (0, 0, 0)
    /// Whether the last run used the GPU, and how long the network itself took (seconds).
    public private(set) var lastRunAccelerated = false
    public private(set) var lastSeconds: Double = 0
    /// Whether the last photo was brightened or given more contrast before the network saw it.
    public private(set) var lastExposureCorrected = false

    /// Loads a compiled model (.mlmodelc), or compiles an .mlpackage first (used by the test bench).
    public init(url: URL, accelerate: Bool = false) throws {
        var compiled = url
        if url.pathExtension == "mlpackage" || url.pathExtension == "mlmodel" {
            compiled = try MLModel.compileModel(at: url)
        }
        compiledURL = compiled
        self.accelerate = accelerate
        // Load one model now so a broken file fails here, not on the first photo.
        let first: MLModel
        if accelerate, CutoutNetwork.gpuTrust != false, let g = try? load(.cpuAndGPU) {
            gpuModel = g; first = g
        } else {
            let c = try load(.cpuOnly)
            cpuModel = c; first = c
        }
        let inputs = first.modelDescription.inputDescriptionsByName
        let outputs = first.modelDescription.outputDescriptionsByName
        inputName = inputs["image"] != nil ? "image" : (inputs.keys.sorted().first ?? "image")
        outputName = outputs["mask_logits"] != nil ? "mask_logits" : (outputs.keys.sorted().first ?? "mask_logits")
    }

    private func load(_ units: MLComputeUnits) throws -> MLModel {
        let config = MLModelConfiguration()
        config.computeUnits = units
        return try MLModel(contentsOf: compiledURL, configuration: config)
    }

    /// Whether the app tries the GPU. Off: on an iPhone 11 (2.3 GB app memory limit) holding the
    /// GPU and CPU copies of the model for the first-photo check went over the limit and iOS closed
    /// the app (phone log, 25 Nov 2026). Before turning it on again, measure memory on the phone
    /// and run the check with only one copy loaded at a time.
    public static let useGPU = false

    /// The model bundled with the app, if present.
    public static func bundled() -> CutoutNetwork? {
        if let u = Bundle.main.url(forResource: "BiRefNetLite", withExtension: "mlmodelc"),
           let n = try? CutoutNetwork(url: u, accelerate: useGPU) {
            return n
        }
        if let p = ProcessInfo.processInfo.environment["CLEARCUT_MODEL"], let n = try? CutoutNetwork(url: URL(fileURLWithPath: p)) {
            return n
        }
        return nil
    }

    /// Frees the loaded model and the working memory it holds on to after a prediction (well over
    /// a gigabyte for this network). It is loaded again, from the compiled cache, when next needed.
    public func unload() {
        lock.lock()
        cpuModel = nil
        gpuModel = nil
        lock.unlock()
    }

    // MARK: GPU trust

    private static var trustKey: String {
        "network.gpu.v1." + ProcessInfo.processInfo.operatingSystemVersionString
    }

    /// nil: not checked yet on this iOS version. true/false: the verdict.
    static var gpuTrust: Bool? {
        get { UserDefaults.standard.object(forKey: trustKey) as? Bool }
        set { UserDefaults.standard.set(newValue, forKey: trustKey) }
    }

    /// Two raw outputs describe the same cutout: the outlines overlap almost entirely and the
    /// probabilities differ by very little on average.
    static func agree(_ a: [Float], _ b: [Float]) -> Bool {
        guard a.count == b.count, !a.isEmpty, sane(a) else { return false }
        let pa = probabilities(a), pb = probabilities(b)
        var inter = 0, uni = 0
        var diff: Double = 0
        for i in 0..<pa.count {
            let x = pa[i] > 0.5, y = pb[i] > 0.5
            if x && y { inter += 1 }
            if x || y { uni += 1 }
            diff += Double(abs(pa[i] - pb[i]))
        }
        let iou = uni == 0 ? 1 : Double(inter) / Double(uni)
        return iou > 0.985 && diff / Double(pa.count) < 0.02
    }

    static func sane(_ raw: [Float]) -> Bool {
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for v in raw {
            if !v.isFinite { return false }
            lo = min(lo, v); hi = max(hi, v)
        }
        return hi - lo > 1e-3
    }

    /// The output is documented as logits, but if every value already lies in 0...1 it is a
    /// probability; applying the sigmoid again would push everything over one half.
    static func probabilities(_ raw: [Float]) -> [Float] {
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for v in raw { lo = min(lo, v); hi = max(hi, v) }
        if lo >= 0 && hi <= 1 { return raw }
        return raw.map { 1 / (1 + expf(-max(-80, min(80, $0)))) }
    }

    // MARK: Running

    private func run(_ model: MLModel, _ provider: MLFeatureProvider) throws -> [Float]? {
        let s = CutoutNetwork.side
        let result = try model.prediction(from: provider)
        guard let out = result.featureValue(for: outputName)?.multiArrayValue else { return nil }
        let shape = out.shape.map { $0.intValue }, strides = out.strides.map { $0.intValue }
        guard shape.count >= 2, shape[shape.count - 1] == s, shape[shape.count - 2] == s else { return nil }
        // GPU outputs can have padded rows, so read through the strides.
        let sy = strides[shape.count - 2], sx = strides[shape.count - 1]
        var raw = [Float](repeating: 0, count: s * s)
        switch out.dataType {
        case .float32:
            let src = out.dataPointer.assumingMemoryBound(to: Float.self)
            for y in 0..<s { for x in 0..<s { raw[y * s + x] = src[y * sy + x * sx] } }
        case .double:
            let src = out.dataPointer.assumingMemoryBound(to: Double.self)
            for y in 0..<s { for x in 0..<s { raw[y * s + x] = Float(src[y * sy + x * sx]) } }
        default:
            #if arch(arm64)
            if out.dataType == .float16 {
                let src = out.dataPointer.assumingMemoryBound(to: Float16.self)
                for y in 0..<s { for x in 0..<s { raw[y * s + x] = Float(src[y * sy + x * sx]) } }
                return raw
            }
            #endif
            let lead = [NSNumber](repeating: 0, count: shape.count - 2)
            for y in 0..<s {
                for x in 0..<s { raw[y * s + x] = out[lead + [NSNumber(value: y), NSNumber(value: x)]].floatValue }
            }
        }
        return raw
    }

    /// Raw network output for a prepared input, on the GPU when it has been checked.
    private func predict(_ provider: MLFeatureProvider) throws -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        let started = Date()
        defer { lastSeconds = Date().timeIntervalSince(started) }
        if accelerate, CutoutNetwork.gpuTrust != false {
            if gpuModel == nil { gpuModel = try? load(.cpuAndGPU) }
            if let g = gpuModel {
                let fast = try? run(g, provider)
                if CutoutNetwork.gpuTrust == nil {
                    // First photo on this iOS version: check the GPU against the CPU.
                    if cpuModel == nil { cpuModel = try load(.cpuOnly) }
                    guard let reference = try run(cpuModel!, provider) else { return nil }
                    let ok = fast.map { CutoutNetwork.agree($0, reference) } ?? false
                    CutoutNetwork.gpuTrust = ok
                    if ok { cpuModel = nil } else { gpuModel = nil }
                    lastRunAccelerated = false
                    return reference
                }
                if let f = fast, CutoutNetwork.sane(f) {
                    lastRunAccelerated = true
                    return f
                }
                CutoutNetwork.gpuTrust = false
                gpuModel = nil
            }
        }
        if cpuModel == nil { cpuModel = try load(.cpuOnly) }
        lastRunAccelerated = false
        return try run(cpuModel!, provider)
    }

    // MARK: Exposure

    /// A tone curve for dark or flat photos, so the network sees the item clearly: the darkest
    /// and brightest 1% are stretched to the full range and dark photos are brightened
    /// (mid-tones only, never darkened). Well-exposed photos are left exactly as they are.
    /// The same curve is used for all three channels, so colours keep their hue.
    static func exposureCurve(_ rgba: [UInt8]) -> [UInt8]? {
        var hist = [Int](repeating: 0, count: 256)
        var i = 0, n = 0
        while i < rgba.count {
            let y = (54 * Int(rgba[i]) + 183 * Int(rgba[i + 1]) + 19 * Int(rgba[i + 2])) >> 8
            hist[min(255, y)] += 1
            i += 4 * 3   // every third pixel is plenty
            n += 1
        }
        guard n > 0 else { return nil }
        func percentile(_ q: Double) -> Int {
            let target = Int(Double(n) * q)
            var acc = 0
            for v in 0..<256 { acc += hist[v]; if acc > target { return v } }
            return 255
        }
        let p1 = percentile(0.01), p50 = percentile(0.5), p99 = percentile(0.99)
        let dark = p50 < 70, flat = p99 - p1 < 80
        guard dark || flat else { return nil }
        let lo = Double(p1), span = Double(max(24, p99 - p1))
        let mid = min(0.95, max(0.05, (Double(p50) - lo) / span))
        // Gamma that lifts the median towards 0.42; at most a strong lift, never a darkening.
        let gamma = dark ? min(1, max(0.45, log(0.42) / log(mid))) : 1
        var lut = [UInt8](repeating: 0, count: 256)
        for v in 0..<256 {
            let t = min(1, max(0, (Double(v) - lo) / span))
            lut[v] = UInt8(min(255, max(0, (pow(t, gamma) * 255).rounded())))
        }
        return lut
    }

    /// Foreground probability (0...1) for an image, at the image's own size.
    public func probability(of image: CGImage) throws -> Plane? {
        let s = CutoutNetwork.side
        guard var rgba = RGBAImage(cgImage: image, width: s, height: s) else { return nil }
        if let lut = CutoutNetwork.exposureCurve(rgba.pixels) {
            rgba.pixels.withUnsafeMutableBufferPointer { px in
                var i = 0
                while i < px.count { px[i] = lut[Int(px[i])]; px[i + 1] = lut[Int(px[i + 1])]; px[i + 2] = lut[Int(px[i + 2])]; i += 4 }
            }
            lastExposureCorrected = true
        } else {
            lastExposureCorrected = false
        }
        let input = try MLMultiArray(shape: [1, 3, NSNumber(value: s), NSNumber(value: s)], dataType: .float32)
        let mean: [Float] = [0.485, 0.456, 0.406], std: [Float] = [0.229, 0.224, 0.225]
        let plane = s * s
        let dst = input.dataPointer.assumingMemoryBound(to: Float.self)
        rgba.pixels.withUnsafeBufferPointer { px in
            for i in 0..<plane {
                for c in 0..<3 {
                    dst[c * plane + i] = (Float(px[i * 4 + c]) / 255 - mean[c]) / std[c]
                }
            }
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: input)])
        guard let raw = try predict(provider), raw.count == plane else { return nil }
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude, sum: Float = 0
        for v in raw { lo = min(lo, v); hi = max(hi, v); sum += v }
        lastOutputRange = (lo, hi, sum / Float(plane))
        let p = Plane(width: s, height: s, data: CutoutNetwork.probabilities(raw))
        return p.resized(width: image.width, height: image.height)
    }
}
