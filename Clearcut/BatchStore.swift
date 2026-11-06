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

    struct ExportResult: Identifiable {
        let id = UUID()
        let saved: Int
        let failed: Int
        let thumbs: [UIImage]
    }

    private let dir: URL
    private var previewTask: Task<Void, Never>?
    private var importQueue: [PhotosPickerItem] = []
    private var importRunning = false

    init() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClearcutBatch", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var initial = Look()
        if let data = UserDefaults.standard.data(forKey: "look"),
           let saved = try? JSONDecoder().decode(Look.self, from: data) {
            initial = saved
        }
        if initial.backdrop == .photo { initial.backdrop = .colour(RGB(1, 1, 1)) }
        look = initial
    }

    private func saveLook() {
        if let data = try? JSONEncoder().encode(look) {
            UserDefaults.standard.set(data, forKey: "look")
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
                        var item = BatchItem(id: id, originalURL: p.originalURL, originalSize: p.originalSize)
                        item.smallOriginal = p.smallOriginal
                        item.cutoutURL = p.cutoutURL
                        item.smallCutout = p.smallCutout
                        item.status = p.cutoutURL == nil ? .noSubject : .ready
                        item.removed = p.cutoutURL != nil
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
        let originalSize: CGSize
        let smallOriginal: CGImage?
        let cutoutURL: URL?
        let smallCutout: CGImage?
    }

    nonisolated static func prepare(data: Data, id: UUID, dir: URL) -> Prepared? {
        guard let cg = ImageFiles.loadOriented(data, maxPixel: 3200) else { return nil }
        let originalURL = dir.appendingPathComponent("\(id.uuidString)-original")
        do { try data.write(to: originalURL) } catch { return nil }
        let size = CGSize(width: cg.width, height: cg.height)
        let small = ImageFiles.scaled(cg, maxSide: 640)

        var cutoutURL: URL?
        var smallCut: CGImage?
        if let subject = try? Cutout.subject(from: cg),
           let cutCG = Renderer.context.createCGImage(subject, from: subject.extent, format: .RGBA8, colorSpace: Renderer.sRGB),
           let png = ImageFiles.encode(cutCG, type: .png) {
            let url = dir.appendingPathComponent("\(id.uuidString)-cutout.png")
            if (try? png.write(to: url)) != nil {
                cutoutURL = url
                smallCut = ImageFiles.scaled(cutCG, maxSide: 640)
            }
        }
        return Prepared(originalURL: originalURL, originalSize: size, smallOriginal: small,
                        cutoutURL: cutoutURL, smallCutout: smallCut)
    }

    // MARK: Previews

    nonisolated static func renderSmall(cut: CGImage, originalSize: CGSize, place: Renderer.Placement,
                                        look: Look, photo: CIImage?) -> UIImage? {
        let size = Renderer.canvasSize(look: look, originalSize: originalSize, longSide: 720)
        let image = Renderer.compose(cutout: CIImage(cgImage: cut), look: look, place: place, photo: photo, size: size)
        guard let cg = Renderer.cgImage(image, size: size) else { return nil }
        return UIImage(cgImage: cg)
    }

    func renderPreview(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }), item.removed, let cut = item.smallCutout else { return }
        let look = self.look, photo = backdropPhoto
        let place = Renderer.Placement(offset: item.offset, scale: item.scale)
        let size = item.originalSize
        Task {
            let image = await Task.detached(priority: .userInitiated) {
                Box(BatchStore.renderSmall(cut: cut, originalSize: size, place: place, look: look, photo: photo))
            }.value.value
            if let image, self.look == look { previews[id] = image }
        }
    }

    func refreshPreviews() {
        previewTask?.cancel()
        let look = self.look, photo = backdropPhoto
        let jobs: [(UUID, CGImage, CGSize, Renderer.Placement)] = items.compactMap { item in
            guard item.removed, let cut = item.smallCutout else { return nil }
            return (item.id, cut, item.originalSize, Renderer.Placement(offset: item.offset, scale: item.scale))
        }
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            for job in jobs {
                if Task.isCancelled { return }
                let image = await Task.detached(priority: .userInitiated) {
                    Box(BatchStore.renderSmall(cut: job.1, originalSize: job.2, place: job.3, look: look, photo: photo))
                }.value.value
                if Task.isCancelled { return }
                if let image { previews[job.0] = image }
            }
        }
    }

    // MARK: Editing

    func update(_ id: UUID, _ change: (inout BatchItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        renderPreview(for: id)
    }

    func setAllRemoved(_ removed: Bool) {
        for i in items.indices where items[i].canRemove {
            items[i].removed = removed
        }
        refreshPreviews()
    }

    func delete(_ id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: item.originalURL)
            if let c = item.cutoutURL { try? FileManager.default.removeItem(at: c) }
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
            let box = await Task.detached(priority: .userInitiated) { Box(ImageFiles.loadOriented(data, maxPixel: 3200)) }.value
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
            let look = self.look, photo = backdropPhoto
            exportProgress = (0, list.count)
            var saved = 0, failed = 0
            var thumbs: [UIImage] = []
            for (i, item) in list.enumerated() {
                let result = await Task.detached(priority: .userInitiated) {
                    BatchStore.exportData(item: item, look: look, photo: photo)
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

    nonisolated static func exportData(item: BatchItem, look: Look, photo: CIImage?) -> Exported? {
        if !item.removed || item.cutoutURL == nil {
            guard let data = try? Data(contentsOf: item.originalURL) else { return nil }
            let thumb = item.smallOriginal.map { UIImage(cgImage: $0) } ?? UIImage()
            return Exported(data: data, thumb: thumb)
        }
        guard let url = item.cutoutURL, let cut = CIImage(contentsOf: url) else { return nil }
        let size = Renderer.canvasSize(look: look, originalSize: item.originalSize, longSide: CGFloat(look.exportLongSide))
        let image = Renderer.compose(cutout: cut, look: look,
                                     place: Renderer.Placement(offset: item.offset, scale: item.scale),
                                     photo: photo, size: size)
        guard let cg = Renderer.cgImage(image, size: size) else { return nil }
        let png = look.preferPNG || look.backdrop == .transparent
        guard let data = ImageFiles.encode(cg, type: png ? .png : .jpeg, quality: 0.93) else { return nil }
        let thumb = UIImage(cgImage: ImageFiles.scaled(cg, maxSide: 300) ?? cg)
        return Exported(data: data, thumb: thumb)
    }
}
