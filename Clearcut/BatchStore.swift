import SwiftUI
import PhotosUI
import Photos
import CoreImage
import UniformTypeIdentifiers

@MainActor
final class BatchStore: ObservableObject {
    @Published var items: [BatchItem] = []
    @Published var look: Look {
        didSet {
            guard look != oldValue else { return }
            saveLook()
            refreshPreviews()
        }
    }
    @Published private(set) var backdropPhoto: CIImage?
    @Published private(set) var backdropPhotoID = 0
    @Published var previews: [UUID: UIImage] = [:]
    @Published var importing: (done: Int, total: Int)?
    @Published var exportProgress: (done: Int, total: Int)?
    @Published var exportResult: ExportResult?
    @Published var message: String?
    /// The photo the user is looking at in a tool screen; it is re-rendered first.
    var focusID: UUID?

    struct ExportResult: Identifiable {
        let id = UUID()
        let saved: Int
        let failed: Int
        let thumbs: [UIImage]
    }

    nonisolated static let previewLongSide: CGFloat = 1100

    private let dir: URL
    private var previewTask: Task<Void, Never>?
    private var importQueue: [PhotosPickerItem] = []
    private var importRunning = false

    init() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClearcutBatch", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var initial = Look()
        if let data = UserDefaults.standard.data(forKey: Look.storageKey),
           let saved = try? JSONDecoder().decode(Look.self, from: data) {
            initial = saved
        }
        if initial.backdrop == .photo { initial.backdrop = Look().backdrop }
        look = initial
    }

    private func saveLook() {
        if let data = try? JSONEncoder().encode(look) {
            UserDefaults.standard.set(data, forKey: Look.storageKey)
        }
    }

    var anyRemoved: Bool { items.contains { $0.removed } }
    var busy: Bool { importing != nil || exportProgress != nil }

    // MARK: Import and cut out

    func add(_ picks: [PhotosPickerItem]) {
        guard !picks.isEmpty else { return }
        importQueue.append(contentsOf: picks)
        let total = (importing?.total ?? 0) + picks.count
        importing = (importing?.done ?? 0, total)
        guard !importRunning else { return }
        importRunning = true
        Task {
            while !importQueue.isEmpty {
                let pick = importQueue.removeFirst()
                if let data = try? await pick.loadTransferable(type: Data.self) {
                    let id = UUID()
                    let folder = dir
                    let prepared = await Task.detached(priority: .userInitiated) {
                        BatchStore.prepare(data: data, id: id, dir: folder)
                    }.value
                    if let p = prepared {
                        var item = BatchItem(id: id, originalURL: p.originalURL, pixelSize: p.pixelSize)
                        item.smallOriginal = p.smallOriginal
                        item.maskURL = p.maskURL
                        item.smallMask = p.smallMask
                        item.bbox = p.bbox
                        item.status = p.maskURL == nil ? .noSubject : .ready
                        item.removed = p.maskURL != nil
                        items.append(item)
                        renderPreview(for: id)
                    }
                }
                if let i = importing { importing = (i.done + 1, i.total) }
            }
            importing = nil
            importRunning = false
            let missing = items.filter { $0.status == .noSubject }.count
            if missing > 0 {
                message = missing == 1
                    ? "Clearcut couldn't find an item in one photo, so it's been kept as it is."
                    : "Clearcut couldn't find an item in \(missing) photos, so they've been kept as they are."
            }
        }
    }

    struct Prepared: @unchecked Sendable {
        let originalURL: URL
        let pixelSize: CGSize
        let smallOriginal: CGImage?
        let maskURL: URL?
        let smallMask: CGImage?
        let bbox: CGRect
    }

    nonisolated static func prepare(data: Data, id: UUID, dir: URL) -> Prepared? {
        let originalURL = dir.appendingPathComponent("\(id.uuidString)-original")
        do { try data.write(to: originalURL) } catch { return nil }
        // Full resolution, orientation applied. Nothing is resized for output.
        let fullSide = ImageFiles.orientedSize(data).map { Int(max($0.width, $0.height)) } ?? 8192
        guard let full = ImageFiles.loadOriented(data, maxPixel: min(fullSide, 8192)) else { return nil }
        let size = CGSize(width: full.width, height: full.height)
        let small = ImageFiles.scaled(full, maxSide: previewLongSide)

        var maskURL: URL?
        var smallMask: CGImage?
        var bbox = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let mask = try? Cutout.mask(for: full), let png = ImageFiles.encode(mask, type: .png) {
            let url = dir.appendingPathComponent("\(id.uuidString)-mask.png")
            if (try? png.write(to: url)) != nil {
                maskURL = url
                if let small {
                    smallMask = ImageFiles.scaledGray(mask, to: CGSize(width: small.width, height: small.height))
                }
                bbox = Cutout.boundingBox(of: smallMask ?? mask)
            }
        }
        return Prepared(originalURL: originalURL, pixelSize: size, smallOriginal: small,
                        maskURL: maskURL, smallMask: smallMask, bbox: bbox)
    }

    // MARK: Previews

    nonisolated static func renderSmall(original: CGImage, mask: CGImage, bbox: CGRect, look: Look, photo: CIImage?) -> UIImage? {
        let size = CGSize(width: original.width, height: original.height)
        let image = Renderer.compose(original: CIImage(cgImage: original), mask: Renderer.maskImage(mask),
                                     bbox: bbox, look: look, photo: photo, size: size)
        guard let cg = Renderer.cgImage(image, size: size) else { return nil }
        return UIImage(cgImage: cg)
    }

    func renderPreview(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }), item.removed,
              let original = item.smallOriginal, let mask = item.smallMask else { return }
        let look = self.look, photo = Box(backdropPhoto), bbox = item.bbox
        let o = Box(original), m = Box(mask)
        Task {
            let image = await Task.detached(priority: .userInitiated) {
                Box(BatchStore.renderSmall(original: o.value, mask: m.value, bbox: bbox, look: look, photo: photo.value))
            }.value.value
            if let image, self.look == look { previews[id] = image }
        }
    }

    func refreshPreviews() {
        previewTask?.cancel()
        let look = self.look, photo = Box(backdropPhoto)
        var list = items.filter { $0.removed && $0.smallOriginal != nil && $0.smallMask != nil }
        if let f = focusID, let i = list.firstIndex(where: { $0.id == f }) {
            list.insert(list.remove(at: i), at: 0)
        }
        let jobs = list.map { item in
            (item.id, Box(item.smallOriginal!), Box(item.smallMask!), item.bbox)
        }
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 40_000_000)
            for job in jobs {
                if Task.isCancelled { return }
                let image = await Task.detached(priority: .userInitiated) {
                    Box(BatchStore.renderSmall(original: job.1.value, mask: job.2.value, bbox: job.3, look: look, photo: photo.value))
                }.value.value
                if Task.isCancelled { return }
                if let image { previews[job.0] = image }
            }
        }
    }

    // MARK: Editing

    func setRemoved(_ id: UUID, _ removed: Bool) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].canRemove else { return }
        items[i].removed = removed
        if removed { renderPreview(for: id) }
    }

    func setAllRemoved(_ removed: Bool) {
        for i in items.indices where items[i].canRemove {
            items[i].removed = removed
        }
        if removed { refreshPreviews() }
    }

    func delete(_ id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: item.originalURL)
            if let m = item.maskURL { try? FileManager.default.removeItem(at: m) }
        }
        items.removeAll { $0.id == id }
        previews[id] = nil
    }

    func clear() {
        previewTask?.cancel()
        items = []
        previews = [:]
        exportResult = nil
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func setBackdropPhoto(_ pick: PhotosPickerItem) {
        Task {
            guard let data = try? await pick.loadTransferable(type: Data.self) else { return }
            let box = await Task.detached(priority: .userInitiated) { Box(ImageFiles.loadOriented(data, maxPixel: 4096)) }.value
            guard let cg = box.value else { message = "That photo couldn't be opened."; return }
            backdropPhoto = CIImage(cgImage: cg)
            backdropPhotoID += 1
            if look.backdrop == .photo { refreshPreviews() } else { look.backdrop = .photo }
        }
    }

    // MARK: Export

    func exportAll() {
        guard !items.isEmpty, exportProgress == nil else { return }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                message = "Clearcut needs permission to add photos. Open Settings, then Clearcut, then Photos, and allow Add Photos Only."
                return
            }
            let list = items
            let look = self.look, photo = Box(backdropPhoto)
            exportProgress = (0, list.count)
            var saved = 0, failed = 0
            var thumbs: [UIImage] = []
            for (i, item) in list.enumerated() {
                let result = await Task.detached(priority: .userInitiated) {
                    BatchStore.exportData(item: item, look: look, photo: photo.value)
                }.value
                if let result {
                    do {
                        try await PHPhotoLibrary.shared().performChanges {
                            let request = PHAssetCreationRequest.forAsset()
                            request.addResource(with: .photo, data: result.data, options: nil)
                        }
                        saved += 1
                        if thumbs.count < 20 { thumbs.append(result.thumb) }
                    } catch {
                        failed += 1
                    }
                } else {
                    failed += 1
                }
                exportProgress = (i + 1, list.count)
            }
            exportProgress = nil
            exportResult = ExportResult(saved: saved, failed: failed, thumbs: thumbs)
        }
    }

    struct Exported: @unchecked Sendable {
        let data: Data
        let thumb: UIImage
    }

    /// Full-resolution output: same pixel size and framing as the original photo.
    nonisolated static func exportData(item: BatchItem, look: Look, photo: CIImage?) -> Exported? {
        if !item.removed || item.maskURL == nil {
            guard let data = try? Data(contentsOf: item.originalURL) else { return nil }
            let thumb = item.smallOriginal.map { UIImage(cgImage: $0) } ?? UIImage()
            return Exported(data: data, thumb: thumb)
        }
        guard let maskURL = item.maskURL,
              let mask = Renderer.maskImage(url: maskURL),
              let full = ImageFiles.loadOriented(item.originalURL, maxPixel: Int(max(item.pixelSize.width, item.pixelSize.height))) else { return nil }
        let size = CGSize(width: full.width, height: full.height)
        let image = Renderer.compose(original: CIImage(cgImage: full), mask: mask, bbox: item.bbox,
                                     look: look, photo: photo, size: size)
        guard let cg = Renderer.cgImage(image, size: size) else { return nil }
        let png = look.backdrop == .transparent
        guard let data = ImageFiles.encode(cg, type: png ? .png : .jpeg, quality: 0.95) else { return nil }
        let thumb = UIImage(cgImage: ImageFiles.scaled(cg, maxSide: 300) ?? cg)
        return Exported(data: data, thumb: thumb)
    }
}
