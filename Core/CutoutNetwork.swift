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
/// Runs entirely on the device; CPU-only, as the conversion recommends.
public final class CutoutNetwork: @unchecked Sendable {
    public static let side = 1024
    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let lock = NSLock()
    /// Range and mean of the last raw output, for the quality report.
    public private(set) var lastOutputRange: (min: Float, max: Float, mean: Float) = (0, 0, 0)

    /// Loads a compiled model (.mlmodelc), or compiles an .mlpackage first (used by the test bench).
    public init(url: URL) throws {
        var compiled = url
        if url.pathExtension == "mlpackage" || url.pathExtension == "mlmodel" {
            compiled = try MLModel.compileModel(at: url)
        }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: compiled, configuration: config)
        let inputs = model.modelDescription.inputDescriptionsByName
        let outputs = model.modelDescription.outputDescriptionsByName
        inputName = inputs["image"] != nil ? "image" : (inputs.keys.sorted().first ?? "image")
        outputName = outputs["mask_logits"] != nil ? "mask_logits" : (outputs.keys.sorted().first ?? "mask_logits")
    }

    /// The model bundled with the app, if present.
    public static func bundled() -> CutoutNetwork? {
        if let u = Bundle.main.url(forResource: "BiRefNetLite", withExtension: "mlmodelc"), let n = try? CutoutNetwork(url: u) {
            return n
        }
        if let p = ProcessInfo.processInfo.environment["CLEARCUT_MODEL"], let n = try? CutoutNetwork(url: URL(fileURLWithPath: p)) {
            return n
        }
        return nil
    }

    /// Foreground probability (0...1) for an image, at the image's own size.
    public func probability(of image: CGImage) throws -> Plane? {
        let s = CutoutNetwork.side
        guard let rgba = RGBAImage(cgImage: image, width: s, height: s) else { return nil }
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
        lock.lock()
        let result: MLFeatureProvider
        do { result = try model.prediction(from: provider) } catch { lock.unlock(); throw error }
        lock.unlock()
        guard let out = result.featureValue(for: outputName)?.multiArrayValue, out.count == plane else { return nil }
        var raw = [Float](repeating: 0, count: plane)
        if out.dataType == .float32 {
            let src = out.dataPointer.assumingMemoryBound(to: Float.self)
            for i in 0..<plane { raw[i] = src[i] }
        } else {
            for i in 0..<plane { raw[i] = out[i].floatValue }
        }
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude, sum: Float = 0
        for v in raw { lo = min(lo, v); hi = max(hi, v); sum += v }
        lastOutputRange = (lo, hi, sum / Float(plane))
        // The output is documented as logits, but if every value already lies in 0...1 it is a
        // probability; applying the sigmoid again would push everything over one half.
        let isProbability = lo >= 0 && hi <= 1
        var data = raw
        if !isProbability {
            for i in 0..<plane { data[i] = 1 / (1 + expf(-max(-80, min(80, raw[i])))) }
        }
        let p = Plane(width: s, height: s, data: data)
        return p.resized(width: image.width, height: image.height)
    }
}
