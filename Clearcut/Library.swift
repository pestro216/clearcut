import SwiftUI
import UIKit
import ImageIO
import PhotosUI

/// The background library: photographic surfaces bundled with the app, plus the user's own.
///
/// Bundled surfaces come from Clearcut/Backdrops: library.json gives titles and groups, and any
/// other .jpg dropped into that folder appears too (titled from its file name), so the library
/// grows without code changes. Surfaces added in the app are stored on the phone.
struct Surface: Identifiable, Hashable {
    let id: String
    let title: String
    let group: String
    let url: URL
    let thumbURL: URL?
    let pixels: Int
    let custom: Bool
}

@MainActor
final class BackgroundLibrary: ObservableObject {
    @Published private(set) var surfaces: [Surface] = []
    static let groupOrder = ["Wood", "Stone", "Fabric", "Yours"]

    private let customDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    init() { reload() }

    func reload() {
        var list: [Surface] = []
        var listed = Set<String>()
        struct Entry: Decodable { let id: String; let title: String; let group: String; let pixels: Int? }
        struct Manifest: Decodable { let surfaces: [Entry] }
        if let url = Bundle.main.url(forResource: "library", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode(Manifest.self, from: data) {
            for e in m.surfaces {
                guard let u = Bundle.main.url(forResource: e.id, withExtension: "jpg") else { continue }
                list.append(Surface(id: e.id, title: e.title, group: e.group, url: u,
                                    thumbURL: Bundle.main.url(forResource: "thumb-\(e.id)", withExtension: "jpg"),
                                    pixels: e.pixels ?? Self.pixelSize(u), custom: false))
                listed.insert(e.id)
            }
        }
        // Unlisted bundled photos (e.g. your-timber.jpg) appear under "Yours".
        for u in Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: nil) ?? [] {
            let name = u.deletingPathExtension().lastPathComponent
            if name.hasPrefix("thumb-") || listed.contains(name) { continue }
            let title = name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
            list.append(Surface(id: name, title: title, group: "Yours", url: u,
                                thumbURL: Bundle.main.url(forResource: "thumb-\(name)", withExtension: "jpg"),
                                pixels: Self.pixelSize(u), custom: false))
        }
        // Added on this phone.
        let files = (try? FileManager.default.contentsOfDirectory(at: customDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for u in files.filter({ $0.pathExtension == "jpg" && !$0.lastPathComponent.hasPrefix("thumb-") })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let id = "custom-" + u.deletingPathExtension().lastPathComponent
            list.append(Surface(id: id, title: "Your photo", group: "Yours", url: u,
                                thumbURL: customDir.appendingPathComponent("thumb-" + u.lastPathComponent),
                                pixels: Self.pixelSize(u), custom: true))
        }
        surfaces = list
    }

    func surface(_ id: String) -> Surface? { surfaces.first { $0.id == id } }

    func groups() -> [(String, [Surface])] {
        Self.groupOrder.compactMap { g in
            let s = surfaces.filter { $0.group == g }
            return s.isEmpty && g != "Yours" ? nil : (g, s)
        }
    }

    /// Saves a photo from the library as a new background, at its own full resolution.
    func add(_ pick: PhotosPickerItem) async -> String? {
        guard let data = try? await pick.loadTransferable(type: Data.self) else { return nil }
        let dir = customDir
        let name = String(Int(Date().timeIntervalSince1970 * 1000))
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard let cg = ImageIOHelpers.loadOriented(data),
                  let jpg = ImageIOHelpers.encode(cg, type: .jpeg, quality: 0.92) else { return false }
            try? jpg.write(to: dir.appendingPathComponent("\(name).jpg"))
            if let thumb = ImageIOHelpers.loadOriented(data, maxPixel: 240),
               let t = ImageIOHelpers.encode(thumb, type: .jpeg, quality: 0.85) {
                try? t.write(to: dir.appendingPathComponent("thumb-\(name).jpg"))
            }
            return true
        }.value
        reload()
        return ok ? "custom-\(name)" : nil
    }

    func remove(_ s: Surface) {
        guard s.custom else { return }
        try? FileManager.default.removeItem(at: s.url)
        if let t = s.thumbURL { try? FileManager.default.removeItem(at: t) }
        reload()
    }

    nonisolated static func pixelSize(_ url: URL) -> Int {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return 0 }
        return max(p[kCGImagePropertyPixelWidth] as? Int ?? 0, p[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }
}

/// Decoded backdrops, kept small for previews and full size only while exporting.
enum BackdropImages {
    private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()

    static func image(_ url: URL, maxPixel: Int?) -> CGImage? {
        let key = url.path + "|\(maxPixel ?? 0)"
        lock.lock(); defer { lock.unlock() }
        if let c = cache[key] { return c }
        guard let data = try? Data(contentsOf: url), let cg = ImageIOHelpers.loadOriented(data, maxPixel: maxPixel) else { return nil }
        if maxPixel != nil {
            if cache.count > 6 { cache.removeAll() }
            cache[key] = cg
        }
        return cg
    }
}
