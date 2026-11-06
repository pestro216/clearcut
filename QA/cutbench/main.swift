import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ClearcutCore

// cutbench TESTSET OUTDIR [PHOTOS]
// Runs every cutout method on every ground-truth scene, scores them, renders contact sheets,
// writes report.md + results.json, and fails (exit 1) if the shipping method regressed
// against QA/baseline.json.

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: cutbench TESTSET OUTDIR [PHOTOS]"); exit(2) }
let testset = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])
let photosDir = args.count > 3 ? URL(fileURLWithPath: args[3]) : nil
let fm = FileManager.default
try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

func loadCG(_ url: URL) -> CGImage? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return ImageIOHelpers.loadOriented(data)
}
func savePNG(_ img: RGBAImage, _ url: URL, alpha: Bool = false) {
    guard let cg = alpha ? img.makeAlphaCGImage() : img.makeOpaqueCGImage(),
          let d = ImageIOHelpers.encode(cg, type: .png) else { return }
    try? d.write(to: url)
}
func saveJPEG(_ img: RGBAImage, _ url: URL) {
    guard let cg = img.makeOpaqueCGImage(), let d = ImageIOHelpers.encode(cg, type: .jpeg, quality: 0.9) else { return }
    try? d.write(to: url)
}
func memoryMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}
func time<T>(_ f: () throws -> T) rethrows -> (T, Double) {
    let t = Date(); let r = try f(); return (r, Date().timeIntervalSince(t))
}

// Sheet helpers
func blit(_ dst: inout RGBAImage, _ src: RGBAImage, _ x0: Int, _ y0: Int) {
    for y in 0..<src.height where y0 + y < dst.height {
        for x in 0..<src.width where x0 + x < dst.width {
            let s = (y * src.width + x) * 4, d = ((y0 + y) * dst.width + x0 + x) * 4
            dst.pixels[d] = src.pixels[s]; dst.pixels[d + 1] = src.pixels[s + 1]; dst.pixels[d + 2] = src.pixels[s + 2]; dst.pixels[d + 3] = 255
        }
    }
}
func crop(_ img: RGBAImage, cx: Int, cy: Int, size: Int, zoom: Int) -> RGBAImage {
    var out = RGBAImage(width: size * zoom, height: size * zoom, fill: (0, 0, 0))
    let x0 = max(0, min(img.width - size, cx - size / 2)), y0 = max(0, min(img.height - size, cy - size / 2))
    for y in 0..<(size * zoom) {
        for x in 0..<(size * zoom) {
            let sx = x0 + x / zoom, sy = y0 + y / zoom
            let s = (sy * img.width + sx) * 4, d = (y * size * zoom + x) * 4
            out.pixels[d] = img.pixels[s]; out.pixels[d + 1] = img.pixels[s + 1]; out.pixels[d + 2] = img.pixels[s + 2]
        }
    }
    return out
}
func flat(_ fg: RGBAImage, _ alpha: [UInt8], on colour: (Float, Float, Float)) -> RGBAImage {
    Compositor.render(photo: fg, alpha: alpha, backdrop: .colour(r: colour.0, g: colour.1, b: colour.2, studioLight: false),
                      shadow: ShadowParams(kind: .none))
}

// Methods
struct Output { var alpha: [UInt8]; var fg: RGBAImage; var seconds: Double; var confidence: String; var notes: [String: Double] }

func runPrevious(_ cg: CGImage, _ photo: RGBAImage) throws -> Output? {
    // The app before this overhaul: one pass, mask stretched to full size and steepened.
    let (seg, t) = try time { try Segmenter.segment(cg, zoom: false) }
    guard let seg else { return nil }
    let up = seg.prob.resized(width: photo.width, height: photo.height)
    let k = min(12, max(3, Float(max(photo.width, photo.height)) / 550))
    let a = up.map { min(1, max(0, ($0 - 0.5) * k + 0.5)) }.toBytes()
    return Output(alpha: a, fg: photo, seconds: t, confidence: "", notes: [:])
}
func runModelOnly(_ cg: CGImage, _ photo: RGBAImage) throws -> Output? {
    let (seg, t) = try time { try Segmenter.segment(cg, zoom: false) }
    guard let seg else { return nil }
    return Output(alpha: seg.prob.resized(width: photo.width, height: photo.height).toBytes(), fg: photo, seconds: t, confidence: "", notes: [:])
}
func runNew(_ cg: CGImage, _ photo: RGBAImage, zoom: Bool = true, colour: Bool = true, guided: Bool = true) throws -> Output? {
    let start = Date()
    guard let seg = try Segmenter.segment(cg, zoom: zoom) else { return nil }
    var o = MatteOptions(); o.colourEvidence = colour; o.guidedRefinement = guided
    let m = Matting.refine(full: photo, segmentation: seg, options: o)
    let fg = Matting.foreground(full: photo, alpha: m.alpha)
    let conf: String
    switch m.confidence { case .good: conf = "good"; case .check(let s): conf = "check: \(s)"; case .failed(let s): conf = "failed: \(s)" }
    return Output(alpha: m.alpha, fg: fg, seconds: Date().timeIntervalSince(start), confidence: conf, notes: m.notes)
}

let methods: [(String, (CGImage, RGBAImage) throws -> Output?)] = [
    ("model only", runModelOnly),
    ("previous app", runPrevious),
    ("new: no zoom pass", { try runNew($0, $1, zoom: false) }),
    ("new: no colour evidence", { try runNew($0, $1, colour: false) }),
    ("new: no edge refinement", { try runNew($0, $1, guided: false) }),
    ("new", { try runNew($0, $1) }),
]
let shipping = "new"

var results: [String: [String: MatteScores]] = [:]
var timings: [String: [String: Double]] = [:]
var confidences: [String: String] = [:]
var report = "# Cutout quality report\n\n"
report += "Generated \(ISO8601DateFormatter().string(from: Date())). Lower is better for errors; higher for IoU and boundary F.\n\n"

let cases = ((try? fm.contentsOfDirectory(atPath: testset.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
let testBackdrop: (Float, Float, Float) = (0.36, 0.55, 0.30)   // green: makes halos obvious
var peakMB = 0.0

for name in cases {
    let dir = testset.appendingPathComponent(name)
    guard let cg = loadCG(dir.appendingPathComponent("photo.jpg")),
          let photo = RGBAImage(cgImage: cg),
          let aCG = loadCG(dir.appendingPathComponent("alpha.png")),
          let fCG = loadCG(dir.appendingPathComponent("fg.png")),
          let refFG = RGBAImage(cgImage: fCG) else { print("skip \(name)"); continue }
    let ref = ImageIOHelpers.grayBytes(aCG, width: photo.width, height: photo.height)
    let backdrop = Compositor.backdropImage(.colour(r: testBackdrop.0, g: testBackdrop.1, b: testBackdrop.2, studioLight: false),
                                            width: photo.width, height: photo.height)
    var outputs: [String: Output] = [:]
    for (mname, run) in methods {
        guard let o = try? run(cg, photo) else { print("\(name) \(mname): no result"); continue }
        outputs[mname] = o
        let s = Metrics.score(alpha: o.alpha, reference: ref, width: photo.width, height: photo.height, photo: photo,
                              foreground: o.fg, referenceForeground: refFG, testBackdrop: backdrop)
        results[name, default: [:]][mname] = s
        timings[name, default: [:]][mname] = o.seconds
        peakMB = max(peakMB, memoryMB())
        if mname == shipping { confidences[name] = o.confidence }
        print(String(format: "%@ | %@ | IoU %.4f BF %.3f bandMAE %.3f missed %.4f kept %.4f dE %.2f dE95 %.2f | %.2fs",
                     name, mname, s.iou, s.boundaryF, s.bandMAE, s.missedItem, s.keptBackground, s.edgeDeltaE, s.edgeDeltaE95, o.seconds))
    }

    // Contact sheet: truth, previous, new on the green test backdrop + a zoom on the worst edge spot of "new".
    guard let new = outputs[shipping], let prev = outputs["previous app"] else { continue }
    let truthC = flat(refFG, ref, on: testBackdrop), prevC = flat(prev.fg, prev.alpha, on: testBackdrop), newC = flat(new.fg, new.alpha, on: testBackdrop)
    var worst = 0, wx = photo.width / 2, wy = photo.height / 2
    let band = 6
    for y in stride(from: band, to: photo.height - band, by: 2) {
        for x in stride(from: band, to: photo.width - band, by: 2) {
            let i = y * photo.width + x
            let r = Int(ref[i])
            if r > 10 && r < 245 {
                let e = abs(Int(new.alpha[i]) - r)
                if e > worst { worst = e; wx = x; wy = y }
            }
        }
    }
    let tw = 560, th = Int(Double(tw) * Double(photo.height) / Double(photo.width))
    let zs = 140, zz = 4
    var sheet = RGBAImage(width: tw * 4 + 50, height: th + zs * zz + 30, fill: (245, 243, 238))
    blit(&sheet, photo.resized(width: tw, height: th), 10, 10)
    blit(&sheet, truthC.resized(width: tw, height: th), 20 + tw, 10)
    blit(&sheet, prevC.resized(width: tw, height: th), 30 + tw * 2, 10)
    blit(&sheet, newC.resized(width: tw, height: th), 40 + tw * 3, 10)
    blit(&sheet, crop(photo, cx: wx, cy: wy, size: zs, zoom: zz), 10, th + 20)
    blit(&sheet, crop(truthC, cx: wx, cy: wy, size: zs, zoom: zz), 20 + tw, th + 20)
    blit(&sheet, crop(prevC, cx: wx, cy: wy, size: zs, zoom: zz), 30 + tw * 2, th + 20)
    blit(&sheet, crop(newC, cx: wx, cy: wy, size: zs, zoom: zz), 40 + tw * 3, th + 20)
    saveJPEG(sheet, outDir.appendingPathComponent("sheet_\(name).jpg"))

    // A finished look: new cutout on a timber-coloured surface with the flatlay shadow.
    let finished = Compositor.render(photo: photo, alpha: new.alpha, backdrop: .colour(r: 0.55, g: 0.27, b: 0.15, studioLight: true),
                                     shadow: ShadowParams())
    saveJPEG(finished.resized(width: 1200, height: Int(1200.0 * Double(photo.height) / Double(photo.width))),
             outDir.appendingPathComponent("finished_\(name).jpg"))
}

// Report tables
func fmt(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }
report += "## Shipping method by scene\n\n| Scene | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% | Time | Confidence |\n|---|---|---|---|---|---|---|---|---|---|\n"
for name in cases {
    guard let s = results[name]?[shipping] else { continue }
    report += "| \(name) | \(fmt(s.iou, 4)) | \(fmt(s.boundaryF, 3)) | \(fmt(s.bandMAE, 3)) | \(fmt(s.missedItem * 100, 2))% | \(fmt(s.keptBackground * 100, 2))% | \(fmt(s.edgeDeltaE, 2)) | \(fmt(s.edgeDeltaE95, 2)) | \(fmt(timings[name]?[shipping] ?? 0, 2)) s | \(confidences[name] ?? "") |\n"
}
report += "\n## Methods compared (mean over scenes)\n\n| Method | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% |\n|---|---|---|---|---|---|---|---|\n"
for (mname, _) in methods {
    let all = cases.compactMap { results[$0]?[mname] }
    guard !all.isEmpty else { continue }
    func avg(_ f: (MatteScores) -> Double) -> Double { all.map(f).reduce(0, +) / Double(all.count) }
    report += "| \(mname) | \(fmt(avg { $0.iou }, 4)) | \(fmt(avg { $0.boundaryF }, 3)) | \(fmt(avg { $0.bandMAE }, 3)) | \(fmt(avg { $0.missedItem } * 100, 2))% | \(fmt(avg { $0.keptBackground } * 100, 2))% | \(fmt(avg { $0.edgeDeltaE }, 2)) | \(fmt(avg { $0.edgeDeltaE95 }, 2)) |\n"
}
report += "\nPeak memory during the run: \(fmt(peakMB, 0)) MB.\n"

// Real photos without reference masks.
if let photosDir, let files = try? fm.contentsOfDirectory(atPath: photosDir.path) {
    let imgs = files.filter { ["jpg", "jpeg", "heic", "png"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
    if !imgs.isEmpty {
        report += "\n## Real photos (no reference mask)\n\n| Photo | Item area | Soft edge share | Edge width | Pieces | Time | Confidence |\n|---|---|---|---|---|---|---|\n"
        for f in imgs {
            guard let cg = loadCG(photosDir.appendingPathComponent(f)), let photo = RGBAImage(cgImage: cg),
                  let o = try? runNew(cg, photo) else { continue }
            let b = Metrics.blind(alpha: o.alpha, width: photo.width, height: photo.height)
            report += "| \(f) | \(fmt(b.area * 100, 1))% | \(fmt(b.softEdgeShare * 100, 1))% | \(fmt(b.edgeWidthPx, 1)) px | \(b.pieces) | \(fmt(o.seconds, 2)) s | \(o.confidence) |\n"
            let finished = Compositor.render(photo: photo, alpha: o.alpha, backdrop: .colour(r: 0.55, g: 0.27, b: 0.15, studioLight: true), shadow: ShadowParams())
            let tw = 900, th = Int(900.0 * Double(photo.height) / Double(photo.width))
            var sheet = RGBAImage(width: tw * 2 + 30, height: th + 20, fill: (245, 243, 238))
            blit(&sheet, photo.resized(width: tw, height: th), 10, 10)
            blit(&sheet, finished.resized(width: tw, height: th), 20 + tw, 10)
            saveJPEG(sheet, outDir.appendingPathComponent("real_\(f).jpg"))
        }
    }
}

// Save results and check for regressions.
struct Out: Codable { var scores: [String: [String: MatteScores]]; var timings: [String: [String: Double]] }
let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
try? enc.encode(Out(scores: results, timings: timings)).write(to: outDir.appendingPathComponent("results.json"))
var candidate: [String: MatteScores] = [:]
for name in cases { if let s = results[name]?[shipping] { candidate[name] = s } }
try? enc.encode(candidate).write(to: outDir.appendingPathComponent("baseline_candidate.json"))

var failures: [String] = []
let baselineURL = testset.deletingLastPathComponent().appendingPathComponent("baseline.json")
let repoBaseline = URL(fileURLWithPath: "QA/baseline.json")
if let data = (try? Data(contentsOf: repoBaseline)) ?? (try? Data(contentsOf: baselineURL)),
   let base = try? JSONDecoder().decode([String: MatteScores].self, from: data) {
    for (name, b) in base {
        guard let s = candidate[name] else { failures.append("\(name): no result"); continue }
        if s.iou < b.iou - 0.01 { failures.append("\(name): IoU \(fmt(s.iou, 4)) < \(fmt(b.iou, 4))") }
        if s.boundaryF < b.boundaryF - 0.03 { failures.append("\(name): boundary F \(fmt(s.boundaryF, 3)) < \(fmt(b.boundaryF, 3))") }
        if s.edgeDeltaE > b.edgeDeltaE * 1.15 + 0.3 { failures.append("\(name): edge ΔE \(fmt(s.edgeDeltaE, 2)) > \(fmt(b.edgeDeltaE, 2))") }
        if s.missedItem > b.missedItem + 0.01 { failures.append("\(name): missed item rose") }
        if s.keptBackground > b.keptBackground + 0.01 { failures.append("\(name): kept background rose") }
    }
    report += failures.isEmpty ? "\n**Regression check: passed** against QA/baseline.json.\n" : "\n**Regression check: FAILED**\n\n" + failures.map { "- \($0)" }.joined(separator: "\n") + "\n"
} else {
    report += "\nNo baseline yet; baseline_candidate.json can be committed as QA/baseline.json.\n"
}
try? report.write(to: outDir.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
print(report)
exit(failures.isEmpty ? 0 : 1)
