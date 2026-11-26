import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

/// The batch: imports photos, cuts them out at full resolution with the Core engine,
/// keeps small copies for a responsive grid, and exports finished photos to Photos.
///
/// Memory: only one photo is ever held at full resolution (while it is being processed or
/// exported). Everything else lives on disk, plus ~0.5 MB per photo for the grid.
@MainActor
final class BatchStore: ObservableObject {
    @Published var items: [BatchItem] = [] { didSet { saveManifest() } }
    /// Photos per batch. Each photo is cut out one at a time, so memory doesn't grow with the
    /// batch, but a long batch keeps the phone busy and warm; 40 is a sensible sitting.
    nonisolated static let maxPerBatch = 40
    /// Room left in the batch, counting photos still waiting to be imported.
    var room: Int { max(0, BatchStore.maxPerBatch - items.count - queue.count) }
    @Published var look: Look {
        didSet {
            guard look != oldValue else { return }
            if let d = try? JSONEncoder().encode(look) { UserDefaults.standard.set(d, forKey: Look.storageKey) }
            lookVersion += 1
            PreviewRenderer.gate.set(lookVersion)
            if gridSuspended { gridStale = true } else { refreshGrid() }
        }
    }
    /// While a full-screen tool is open the grid can't be seen, so it isn't re-rendered on every change.
    private var gridSuspended = false
    private var gridStale = false
    func suspendGrid(_ on: Bool) {
        gridSuspended = on
        if !on && gridStale { gridStale = false; refreshGrid() }
    }
    /// Bumped whenever the finished appearance changes; views key their renders on it.
    @Published private(set) var lookVersion = 0
    @Published var grid: [UUID: UIImage] = [:]
    @Published var importing: (done: Int, total: Int)?
    @Published var exportProgress: (done: Int, total: Int)?
    @Published var exportResult: ExportResult?
    @Published var message: String?

    let library: BackgroundLibrary

    /// What the surface under the items looks like, learned from clear photos and kept between
    /// launches (most batches are shot on the same surface). Close-ups and linings rely on it.
    private(set) var surface: SurfaceModel? {
        didSet { if let d = try? JSONEncoder().encode(surface) { UserDefaults.standard.set(d, forKey: "surface.v1") } }
    }

    struct ExportResult: Identifiable {
        let id = UUID()
        let saved: Int
        let skipped: Int
        let failures: [String]
        let thumbs: [UIImage]
    }

    nonisolated static let previewSide = 1100
    nonisolated static let gridSide = 340

    private let dir: URL
    private var gridTask: Task<Void, Never>?
    private enum Source { case pick(PhotosPickerItem), file(URL) }
    private var queue: [Source] = []
    /// Photos shown with a quick cutout, waiting for the full one, oldest first.
    private var refineQueue: [UUID] = []
    private var running = false

    init(library: BackgroundLibrary) {
        self.library = library
        // The batch lives in Application Support (not backed up), so it survives the app being
        // closed by iOS and carries on when reopened. The old temporary folder is cleared.
        let fm = FileManager.default
        try? fm.removeItem(at: fm.temporaryDirectory.appendingPathComponent("ClearcutBatch", isDirectory: true))
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        var batchDir = support.appendingPathComponent("ClearcutBatch", isDirectory: true)
        try? fm.createDirectory(at: batchDir, withIntermediateDirectories: true)
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? batchDir.setResourceValues(rv)
        dir = batchDir
        var initial = Look()
        if let d = UserDefaults.standard.data(forKey: Look.storageKey), let saved = try? JSONDecoder().decode(Look.self, from: d) {
            initial = saved
        }
        if case .surface(let id) = initial.backdrop, library.surface(id) == nil { initial.backdrop = Look().backdrop }
        look = initial
        if let d = UserDefaults.standard.data(forKey: "surface.v1"), let m = try? JSONDecoder().decode(SurfaceModel?.self, from: d) {
            surface = m
        }
        restore()
    }

    // MARK: Saved batch

    /// What is kept on disk about each photo. File names are relative to the batch folder,
    /// because the app's folder path can change between installs.
    private struct Saved: Codable {
        var id: UUID
        var status: BatchItem.Status
        var removed: Bool
        var edited: Bool
        var triedWithSurface: Bool
        var original: String
        var width: Double
        var height: Double
        var alpha: String?
        var previewPhoto: String?
        var previewAlpha: String?
    }

    private var manifestURL: URL { dir.appendingPathComponent("batch.json") }
    private static let inProgressKey = "batch.inProgress.v1"
    private var restoring = false

    private func saveManifest() {
        guard !restoring else { return }
        let saved = items.map { i in
            Saved(id: i.id, status: i.status, removed: i.removed, edited: i.edited, triedWithSurface: i.triedWithSurface,
                  original: i.originalURL.lastPathComponent, width: Double(i.pixelSize.width), height: Double(i.pixelSize.height),
                  alpha: i.alphaURL?.lastPathComponent, previewPhoto: i.previewPhotoURL?.lastPathComponent,
                  previewAlpha: i.previewAlphaURL?.lastPathComponent)
        }
        if let d = try? JSONEncoder().encode(saved) { try? d.write(to: manifestURL, options: .atomic) }
    }

    /// Reopens the batch the app was working on when it was last closed. A photo that was being
    /// cut out at that moment may be what made iOS close the app, so it is skipped and kept as
    /// the original rather than tried again.
    private func restore() {
        let fm = FileManager.default
        guard let d = try? Data(contentsOf: manifestURL), let saved = try? JSONDecoder().decode([Saved].self, from: d) else { return }
        let crashed = UserDefaults.standard.string(forKey: BatchStore.inProgressKey).flatMap(UUID.init(uuidString:))
        UserDefaults.standard.removeObject(forKey: BatchStore.inProgressKey)
        func url(_ name: String?) -> URL? {
            guard let name else { return nil }
            let u = dir.appendingPathComponent(name)
            return fm.fileExists(atPath: u.path) ? u : nil
        }
        restoring = true
        var restored: [BatchItem] = []
        for s in saved {
            guard let original = url(s.original) else { continue }
            var item = BatchItem(id: s.id, originalURL: original)
            item.status = s.status
            item.removed = s.removed
            item.edited = s.edited
            item.triedWithSurface = s.triedWithSurface
            item.pixelSize = CGSize(width: s.width, height: s.height)
            item.alphaURL = url(s.alpha)
            item.previewPhotoURL = url(s.previewPhoto)
            item.previewAlphaURL = url(s.previewAlpha)
            if s.id == crashed {
                item.status = .failed("Skipped: the phone ran out of memory on this photo, kept as the original")
                item.removed = false
                item.triedWithSurface = true
                item.alphaURL = nil
            } else if item.status == .processing {
                refineQueue.append(s.id)
            }
            if item.alphaURL == nil { item.removed = false }
            restored.append(item)
        }
        items = restored
        restoring = false
        saveManifest()
        guard !items.isEmpty else { return }
        // Grid images come back from the saved previews (or the original, for unfinished photos).
        let jobs = items.map { ($0.id, $0.previewPhotoURL ?? $0.originalURL, $0.previewAlphaURL) }
        Task {
            for (id, photoURL, alphaURL) in jobs {
                let r = await Task.detached(priority: .userInitiated) { () -> Box<(RGBAImage, [UInt8]?)?> in
                    autoreleasepool {
                        guard let data = try? Data(contentsOf: photoURL), let size = ImageIOHelpers.orientedSize(data),
                              let cg = ImageIOHelpers.loadOriented(data, maxPixel: 1024), let small = RGBAImage(cgImage: cg) else { return Box(nil) }
                        let g = BatchStore.scaled(Int(size.width), Int(size.height), BatchStore.gridSide)
                        let photo = small.resized(width: g.0, height: g.1)
                        let alpha = alphaURL.flatMap { BatchStore.readAlpha($0, width: g.0, height: g.1) }
                        return Box((photo, alpha))
                    }
                }.value.value
                guard let r, let i = items.firstIndex(where: { $0.id == id }) else { continue }
                items[i].gridPhoto = r.0
                if items[i].status != .processing { items[i].gridAlpha = items[i].removed ? r.1 : nil }
                renderGrid(items[i])
            }
            if !refineQueue.isEmpty {
                importing = (0, refineQueue.count)
                run()
            }
        }
    }

    var busy: Bool { importing != nil || exportProgress != nil }
    var transparent: Bool { if case .transparent = look.backdrop { return true }; return false }
    var attentionCount: Int { items.filter { $0.needsAttention }.count }
    /// Photos that will be saved: those using a cutout. Originals are already in Photos.
    var exportable: [BatchItem] { items.filter { $0.removed && $0.canRemove } }
    var anyRemoved: Bool { items.contains { $0.removed && $0.canRemove } }

    // MARK: Import

    func add(_ picks: [PhotosPickerItem]) {
        let room = self.room
        if picks.count > room {
            message = "A batch holds up to \(BatchStore.maxPerBatch) photos, so \(room == 0 ? "none" : "the first \(room)") of these \(room == 1 ? "was" : "were") added. Save this batch, then start a new one for the rest."
        }
        enqueue(picks.prefix(room).map { .pick($0) })
    }

    /// Adds photos from files (used by the automated simulator check).
    func addFiles(_ urls: [URL]) {
        enqueue(urls.map { .file($0) })
    }

    private func enqueue(_ sources: [Source]) {
        guard !sources.isEmpty else { return }
        queue.append(contentsOf: sources)
        importing = (importing?.done ?? 0, (importing?.total ?? 0) + sources.count)
        run()
    }

    private func run() {
        guard !running else { return }
        running = true
        Task {
            // New photos first: each gets a quick cutout from Apple's subject finder within a
            // fraction of a second, so the whole batch shows up at once. The full cutout then
            // replaces each quick one in turn.
            while !queue.isEmpty || !refineQueue.isEmpty {
                if !queue.isEmpty {
                    let source = queue.removeFirst()
                    let id = UUID()
                    let loaded: Data?
                    switch source {
                    case .pick(let p): loaded = try? await p.loadTransferable(type: Data.self)
                    case .file(let u): loaded = try? Data(contentsOf: u)
                    }
                    var added = false
                    if let data = loaded {
                        let original = dir.appendingPathComponent("\(id.uuidString)-original")
                        if (try? data.write(to: original)) != nil {
                            items.append(BatchItem(id: id, originalURL: original))
                            await quickLook(id: id, data: data)
                            refineQueue.append(id)
                            added = true
                        }
                    }
                    if !added, let p = importing { importing = (p.done + 1, p.total) }
                } else {
                    let id = refineQueue.removeFirst()
                    if let item = items.first(where: { $0.id == id }), let data = try? Data(contentsOf: item.originalURL) {
                        // Remembered until done: if iOS closes the app on this photo, it is skipped on reopening.
                        UserDefaults.standard.set(id.uuidString, forKey: BatchStore.inProgressKey)
                        await cutOut(id: id, data: data)
                        UserDefaults.standard.removeObject(forKey: BatchStore.inProgressKey)
                    }
                    if let p = importing { importing = (p.done + 1, p.total) }
                }
            }
            // Photos that couldn't be cut out before the surface was known get a second go.
            if surface != nil {
                for item in items where !item.triedWithSurface {
                    if case .failed = item.status, let data = try? Data(contentsOf: item.originalURL) {
                        UserDefaults.standard.set(item.id.uuidString, forKey: BatchStore.inProgressKey)
                        await cutOut(id: item.id, data: data)
                        UserDefaults.standard.removeObject(forKey: BatchStore.inProgressKey)
                    }
                }
            }
            importing = nil
            running = false
        }
    }

    /// A quick, rough cutout for the grid while the full one is made.
    private func quickLook(id: UUID, data: Data) async {
        let result = await Task.detached(priority: .userInitiated) {
            Box(BatchStore.quick(data: data))
        }.value.value
        guard let r = result, let i = items.firstIndex(where: { $0.id == id }), items[i].status == .processing else { return }
        items[i].gridPhoto = r.photo
        items[i].gridAlpha = r.alpha
        renderGrid(items[i])
    }

    /// The photo at grid size and, when Apple's subject finder sees an item, its rough cutout.
    nonisolated static func quick(data: Data) -> (photo: RGBAImage, alpha: [UInt8]?)? {
        autoreleasepool {
            guard let size = ImageIOHelpers.orientedSize(data),
                  let cg = ImageIOHelpers.loadOriented(data, maxPixel: 1024), let small = RGBAImage(cgImage: cg) else { return nil }
            let g = scaled(Int(size.width), Int(size.height), gridSide)
            let photo = small.resized(width: g.0, height: g.1)
            guard let prob = Segmenter.quickMask(cg) else { return (photo, nil) }
            Diagnostics.note("quick cutout done")
            return (photo, prob.resized(width: g.0, height: g.1).toBytes())
        }
    }

    private func cutOut(id: UUID, data: Data) async {
        let folder = dir, prior = surface
        let result = await Task.detached(priority: .userInitiated) {
            BatchStore.process(data: data, id: id, dir: folder, surface: prior)
        }.value
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].triedWithSurface = prior != nil
        if let r = result {
            if let l = r.learned { surface = l }
            items[i].pixelSize = r.size
            items[i].alphaURL = r.alphaURL
            items[i].previewPhotoURL = r.previewPhotoURL
            items[i].previewAlphaURL = r.previewAlphaURL
            items[i].gridPhoto = r.gridPhoto
            items[i].gridAlpha = r.gridAlpha
            items[i].status = r.status
            items[i].removed = r.alphaURL != nil
            renderGrid(items[i])
        } else {
            items[i].status = .failed("This photo couldn't be opened")
            items[i].removed = false
            items[i].gridAlpha = nil
            renderGrid(items[i])
        }
    }

    struct Processed: @unchecked Sendable {
        let size: CGSize
        let alphaURL: URL?
        let previewPhotoURL: URL?
        let previewAlphaURL: URL?
        let gridPhoto: RGBAImage?
        let gridAlpha: [UInt8]?
        let status: BatchItem.Status
        var learned: SurfaceModel? = nil
    }

    /// Full-resolution cutout for one photo. Runs off the main thread.
    /// The cutout network bundled with the app (BiRefNet Lite), loaded once.
    nonisolated static let network: CutoutNetwork? = CutoutNetwork.bundled()

    nonisolated static func process(data: Data, id: UUID, dir: URL, surface: SurfaceModel?) -> Processed? {
        autoreleasepool {
            guard let cg = ImageIOHelpers.loadOriented(data), let photo = RGBAImage(cgImage: cg) else { return nil }
            Diagnostics.note("photo decoded")
            let size = CGSize(width: photo.width, height: photo.height)
            let pw = scaled(photo.width, photo.height, previewSide), gw = scaled(photo.width, photo.height, gridSide)
            let preview = photo.resized(width: pw.0, height: pw.1)
            let previewURL = dir.appendingPathComponent("\(id.uuidString)-preview.jpg")
            if let pcg = preview.makeOpaqueCGImage(), let d = ImageIOHelpers.encode(pcg, type: .jpeg, quality: 0.9) { try? d.write(to: previewURL) }
            let gridPhoto = preview.resized(width: gw.0, height: gw.1)

            guard let seg = try? Segmenter.segment(cg, network: BatchStore.network) else {
                return Processed(size: size, alphaURL: nil, previewPhotoURL: previewURL, previewAlphaURL: nil,
                                 gridPhoto: gridPhoto, gridAlpha: nil, status: .failed("No item found, kept as the original"))
            }
            var options = MatteOptions()
            options.surface = surface
            Diagnostics.note("matting starts")
            let matte = Matting.refine(full: photo, segmentation: seg, options: options)
            Diagnostics.note("matting done")
            if case .failed(let why) = matte.confidence {
                return Processed(size: size, alphaURL: nil, previewPhotoURL: previewURL, previewAlphaURL: nil,
                                 gridPhoto: gridPhoto, gridAlpha: nil, status: .failed(why + ", kept as the original"),
                                 learned: matte.learnedSurface)
            }
            let alphaURL = dir.appendingPathComponent("\(id.uuidString)-alpha.png")
            let previewAlphaURL = dir.appendingPathComponent("\(id.uuidString)-preview-alpha.png")
            writeAlpha(matte.alpha, photo.width, photo.height, to: alphaURL)
            let full = Plane(bytes: matte.alpha, width: photo.width, height: photo.height)
            writeAlpha(full.resized(width: pw.0, height: pw.1).toBytes(), pw.0, pw.1, to: previewAlphaURL)
            let gridAlpha = full.resized(width: gw.0, height: gw.1).toBytes()
            let status: BatchItem.Status
            switch matte.confidence {
            case .check(let s): status = .check(s)
            default: status = .ready
            }
            return Processed(size: size, alphaURL: alphaURL, previewPhotoURL: previewURL, previewAlphaURL: previewAlphaURL,
                             gridPhoto: gridPhoto, gridAlpha: gridAlpha, status: status, learned: matte.learnedSurface)
        }
    }

    nonisolated static func scaled(_ w: Int, _ h: Int, _ side: Int) -> (Int, Int) {
        let k = min(1, Double(side) / Double(max(w, h)))
        return (max(1, Int((Double(w) * k).rounded())), max(1, Int((Double(h) * k).rounded())))
    }

    nonisolated static func writeAlpha(_ bytes: [UInt8], _ w: Int, _ h: Int, to url: URL) {
        if let cg = ImageIOHelpers.grayImage(bytes, width: w, height: h), let d = ImageIOHelpers.encode(cg, type: .png) {
            try? d.write(to: url)
        }
    }

    nonisolated static func readAlpha(_ url: URL, width: Int, height: Int) -> [UInt8]? {
        guard let data = try? Data(contentsOf: url), let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return ImageIOHelpers.grayBytes(cg, width: width, height: height)
    }

    // MARK: Rendering

    /// The backdrop for a render, sized for the job.
    nonisolated static func backdropSource(_ look: Look, surfaceURL: URL?, maxPixel: Int?) -> BackdropSource {
        switch look.backdrop {
        case .transparent: return .transparent
        case .colour(let c): return .colour(r: Float(c.r), g: Float(c.g), b: Float(c.b), studioLight: look.studioLight)
        case .surface:
            if let u = surfaceURL, let cg = BackdropImages.image(u, maxPixel: maxPixel) { return .image(cg) }
            return .colour(r: 1, g: 1, b: 1, studioLight: false)
        }
    }

    func surfaceURL(_ look: Look) -> URL? {
        if case .surface(let id) = look.backdrop { return library.surface(id)?.url }
        return nil
    }

    nonisolated static func renderSmall(photo: RGBAImage, alpha: [UInt8], look: Look, surfaceURL: URL?) -> UIImage? {
        let source = backdropSource(look, surfaceURL: surfaceURL, maxPixel: 1400)
        let out = Compositor.render(photo: photo, alpha: alpha, backdrop: source, shadow: look.shadow)
        let transparent: Bool = { if case .transparent = source { return true }; return false }()
        guard let cg = transparent ? out.makeAlphaCGImage() : out.makeOpaqueCGImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    private func renderGrid(_ item: BatchItem) {
        guard let photo = item.gridPhoto else { return }
        if !item.removed || item.gridAlpha == nil {
            if let cg = photo.makeOpaqueCGImage() { grid[item.id] = UIImage(cgImage: cg) }
            return
        }
        let alpha = item.gridAlpha!, look = self.look, url = surfaceURL(look), id = item.id
        let p = Box(photo)
        Task {
            let img = await Task.detached(priority: .userInitiated) {
                Box(BatchStore.renderSmall(photo: p.value, alpha: alpha, look: look, surfaceURL: url))
            }.value.value
            // A quick cutout's render must not land on top of the full one that replaced it.
            guard self.look == look, let img, let now = items.first(where: { $0.id == id }), now.gridAlpha == alpha else { return }
            grid[id] = img
        }
    }

    func refreshGrid() {
        gridTask?.cancel()
        let jobs = items.map { $0 }
        let look = self.look, url = surfaceURL(look)
        gridTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000)
            for item in jobs {
                if Task.isCancelled { return }
                guard let photo = item.gridPhoto else { continue }
                if !item.removed || item.gridAlpha == nil {
                    if let cg = photo.makeOpaqueCGImage() { grid[item.id] = UIImage(cgImage: cg) }
                    continue
                }
                let alpha = item.gridAlpha!, p = Box(photo)
                let img = await Task.detached(priority: .userInitiated) {
                    Box(BatchStore.renderSmall(photo: p.value, alpha: alpha, look: look, surfaceURL: url))
                }.value.value
                if Task.isCancelled { return }
                if let img { grid[item.id] = img }
            }
        }
    }

    /// A larger render for the photo view and the tool screens (1100 px). Renders go through one
    /// queue, reuse the decoded photo and its edge colours, and are skipped once the look has moved
    /// on, so dragging a slider never piles up work.
    func renderPreview(_ id: UUID, look: Look? = nil) async -> UIImage? {
        guard let item = items.first(where: { $0.id == id }), let pu = item.previewPhotoURL else { return nil }
        let look = look ?? self.look, url = surfaceURL(look)
        let removed = item.removed && item.previewAlphaURL != nil
        return await PreviewRenderer.shared.render(id: id, photoURL: pu, alphaURL: removed ? item.previewAlphaURL : nil,
                                                   look: look, surfaceURL: url, version: lookVersion)
    }

    /// A sharper render for zooming in: up to 2600 px from the full-resolution photo and matte.
    func renderDetail(_ id: UUID) async -> UIImage? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        let look = self.look, url = surfaceURL(look)
        let snapshot = item
        return await Task.detached(priority: .userInitiated) { () -> Box<UIImage?> in
            autoreleasepool {
                guard let data = try? Data(contentsOf: snapshot.originalURL),
                      let cg = ImageIOHelpers.loadOriented(data, maxPixel: 2600), let photo = RGBAImage(cgImage: cg) else { return Box(nil) }
                guard snapshot.removed, let au = snapshot.alphaURL,
                      let alpha = BatchStore.readAlpha(au, width: photo.width, height: photo.height) else { return Box(UIImage(cgImage: cg)) }
                let source = BatchStore.backdropSource(look, surfaceURL: url, maxPixel: 2600)
                let out = Compositor.render(photo: photo, alpha: alpha, backdrop: source, shadow: look.shadow)
                let transparent: Bool = { if case .transparent = source { return true }; return false }()
                guard let ocg = transparent ? out.makeAlphaCGImage() : out.makeOpaqueCGImage() else { return Box(nil) }
                return Box(UIImage(cgImage: ocg))
            }
        }.value.value
    }

    // MARK: Corrections

    func setRemoved(_ id: UUID, _ removed: Bool) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].canRemove else { return }
        items[i].removed = removed
        lookVersion += 1
        PreviewRenderer.gate.set(lookVersion)
        renderGrid(items[i])
    }

    func setAllRemoved(_ removed: Bool) {
        for i in items.indices where items[i].canRemove { items[i].removed = removed }
        lookVersion += 1
        PreviewRenderer.gate.set(lookVersion)
        refreshGrid()
    }

    /// Applies touch-up strokes to the full-resolution matte and its smaller copies.
    /// Longest side of the photo and matte used while touching up: sharp enough to zoom in on
    /// edges, small enough to repaint instantly.
    nonisolated static let touchUpSide = 2048

    /// The photo and its matte at touch-up size.
    func touchUpSource(_ id: UUID) async -> TouchUpSource? {
        guard let item = items.first(where: { $0.id == id }), let au = item.alphaURL else { return nil }
        let ou = item.originalURL, size = item.pixelSize
        return await Task.detached(priority: .userInitiated) { () -> TouchUpSource? in
            autoreleasepool {
                let side = BatchStore.touchUpSide
                let (w, h) = BatchStore.scaled(Int(size.width), Int(size.height), side)
                guard let data = try? Data(contentsOf: ou), let cg = ImageIOHelpers.loadOriented(data, maxPixel: side),
                      let photo = RGBAImage(cgImage: cg, width: w, height: h), let image = photo.makeOpaqueCGImage(),
                      let ad = try? Data(contentsOf: au), let acg = ImageIOHelpers.loadOriented(ad, maxPixel: side) else { return nil }
                return TouchUpSource(photo: photo, image: image, alpha: ImageIOHelpers.grayBytes(acg, width: w, height: h))
            }
        }.value
    }

    func applyTouchUp(_ id: UUID, strokes: [BrushStroke]) async {
        guard !strokes.isEmpty, let i = items.firstIndex(where: { $0.id == id }),
              let au = items[i].alphaURL, let pau = items[i].previewAlphaURL else { return }
        let size = items[i].pixelSize
        let ou = items[i].originalURL
        let grid = items[i].gridPhoto.map { ($0.width, $0.height) }
        let result = await Task.detached(priority: .userInitiated) { () -> Box<[UInt8]?> in
            let w = Int(size.width), h = Int(size.height)
            guard var alpha = BatchStore.readAlpha(au, width: w, height: h) else { return Box(nil) }
            // Smart strokes compare colours, so they need the full-size photo.
            var photo: RGBAImage?
            if strokes.contains(where: { $0.reference != nil }), let data = try? Data(contentsOf: ou),
               let cg = ImageIOHelpers.loadOriented(data) {
                photo = RGBAImage(cgImage: cg, width: w, height: h)
            }
            Brush.apply(strokes, to: &alpha, width: w, height: h, photo: photo)
            photo = nil
            BatchStore.writeAlpha(alpha, w, h, to: au)
            let full = Plane(bytes: alpha, width: w, height: h)
            let p = BatchStore.scaled(w, h, BatchStore.previewSide)
            BatchStore.writeAlpha(full.resized(width: p.0, height: p.1).toBytes(), p.0, p.1, to: pau)
            guard let grid else { return Box(nil) }
            return Box(full.resized(width: grid.0, height: grid.1).toBytes())
        }.value.value
        guard let j = items.firstIndex(where: { $0.id == id }) else { return }
        if let g = result { items[j].gridAlpha = g }
        items[j].edited = true
        if case .check = items[j].status { items[j].status = .ready }
        await PreviewRenderer.shared.forget(id)
        lookVersion += 1
        PreviewRenderer.gate.set(lookVersion)
        renderGrid(items[j])
    }

    func delete(_ id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            for u in [item.originalURL, item.alphaURL, item.previewPhotoURL, item.previewAlphaURL].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: u)
            }
        }
        items.removeAll { $0.id == id }
        grid[id] = nil
    }

    func clear() {
        gridTask?.cancel()
        refineQueue = []
        items = []
        grid = [:]
        exportResult = nil
        let fm = FileManager.default
        for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: u) }
        saveManifest()
    }

    // MARK: Export

    func exportAll() {
        guard !exportable.isEmpty, exportProgress == nil else { return }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                message = "Clearcut needs permission to add photos. Open Settings, then Clearcut, then Photos, and allow Add Photos Only."
                return
            }
            let list = exportable
            let skipped = items.count - list.count
            let look = self.look, url = surfaceURL(look)
            exportProgress = (0, list.count)
            var saved = 0
            var failures: [String] = []
            var thumbs: [UIImage] = []
            for (n, item) in list.enumerated() {
                let result = await Task.detached(priority: .userInitiated) {
                    BatchStore.exportData(item: item, look: look, surfaceURL: url)
                }.value
                if let result {
                    do {
                        try await PHPhotoLibrary.shared().performChanges {
                            let request = PHAssetCreationRequest.forAsset()
                            request.addResource(with: .photo, data: result.data, options: nil)
                        }
                        saved += 1
                        if thumbs.count < 20, let t = grid[item.id] { thumbs.append(t) }
                    } catch {
                        failures.append("Photo \(n + 1): Photos refused to save it")
                    }
                } else {
                    failures.append("Photo \(n + 1): couldn't be rendered")
                }
                exportProgress = (n + 1, list.count)
            }
            exportProgress = nil
            exportResult = ExportResult(saved: saved, skipped: skipped, failures: failures, thumbs: thumbs)
        }
    }

    struct Exported: @unchecked Sendable { let data: Data }

    /// Full resolution, original size and framing. One photo in memory at a time.
    nonisolated static func exportData(item: BatchItem, look: Look, surfaceURL: URL?) -> Exported? {
        autoreleasepool {
            guard let data = try? Data(contentsOf: item.originalURL) else { return nil }
            guard item.removed, item.alphaURL != nil, let cg = ImageIOHelpers.loadOriented(data), let photo = RGBAImage(cgImage: cg),
                  let au = item.alphaURL, let alpha = readAlpha(au, width: photo.width, height: photo.height) else { return nil }
            let source = backdropSource(look, surfaceURL: surfaceURL, maxPixel: nil)
            let out = Compositor.render(photo: photo, alpha: alpha, backdrop: source, shadow: look.shadow)
            if case .transparent = source {
                guard let cg = out.makeAlphaCGImage(), let png = ImageIOHelpers.encode(cg, type: .png) else { return nil }
                return Exported(data: png)
            }
            guard let cg = out.makeOpaqueCGImage(), let jpg = ImageIOHelpers.encode(cg, type: .jpeg, quality: 0.95) else { return nil }
            return Exported(data: jpg)
        }
    }
}

/// One queue for large previews. Keeps the last few photos decoded with their edge colours worked
/// out, so a change of look only redoes the backdrop, the shadow and the blend.
actor PreviewRenderer {
    static let shared = PreviewRenderer()

    /// The newest look version; a queued render for an older one is dropped.
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var v = 0
        func set(_ n: Int) { lock.lock(); v = n; lock.unlock() }
        var current: Int { lock.lock(); defer { lock.unlock() }; return v }
    }
    static let gate = Gate()

    private struct Prepared { let photo: RGBAImage; let alpha: [UInt8]?; let fg: RGBAImage?; let cg: CGImage }
    private var cache: [String: Prepared] = [:]
    private var order: [String] = []

    func forget(_ id: UUID) {
        cache = cache.filter { !$0.key.hasPrefix(id.uuidString) }
        order.removeAll { $0.hasPrefix(id.uuidString) }
    }

    func render(id: UUID, photoURL: URL, alphaURL: URL?, look: Look, surfaceURL: URL?, version: Int) -> UIImage? {
        if version < PreviewRenderer.gate.current { return nil }
        let key = id.uuidString + (alphaURL == nil ? "-o" : "-c")
        let prepared: Prepared
        if let p = cache[key] {
            prepared = p
        } else {
            guard let data = try? Data(contentsOf: photoURL), let cg = ImageIOHelpers.loadOriented(data),
                  let photo = RGBAImage(cgImage: cg) else { return nil }
            var alpha: [UInt8]?
            var fg: RGBAImage?
            if let alphaURL, let a = BatchStore.readAlpha(alphaURL, width: photo.width, height: photo.height) {
                alpha = a
                fg = Matting.foreground(full: photo, alpha: a)
            }
            prepared = Prepared(photo: photo, alpha: alpha, fg: fg, cg: cg)
            cache[key] = prepared
            order.removeAll { $0 == key }
            order.append(key)
            while order.count > 6 { cache[order.removeFirst()] = nil }
        }
        guard let alpha = prepared.alpha, let fg = prepared.fg else { return UIImage(cgImage: prepared.cg) }
        if version < PreviewRenderer.gate.current { return nil }
        let source = BatchStore.backdropSource(look, surfaceURL: surfaceURL, maxPixel: 1400)
        let out = Compositor.render(foreground: fg, alpha: alpha, backdrop: source, shadow: look.shadow)
        let transparent: Bool = { if case .transparent = source { return true }; return false }()
        guard let ocg = transparent ? out.makeAlphaCGImage() : out.makeOpaqueCGImage() else { return nil }
        return UIImage(cgImage: ocg)
    }
}
