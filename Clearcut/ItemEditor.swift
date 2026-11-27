import SwiftUI

/// One photo, large. Pinch to zoom in and check edges. Keep or drop the cutout, or touch it up.
struct ItemEditor: View {
    @EnvironmentObject var store: BatchStore
    @Environment(\.dismiss) private var dismiss
    /// The photo shown. Changes when moving on to the next photo that needs a look.
    @State private var id: UUID

    init(id: UUID) { _id = State(initialValue: id) }

    @State private var image: UIImage?
    /// A sharper render, fetched the first time you zoom in.
    @State private var detail: UIImage?
    @State private var detailVersion = -1
    @State private var loadingDetail = false
    @State private var box: CGSize = .zero
    @State private var container: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var tool: Tool?
    @State private var touchUp = false
    /// While the compare button is held, the original photo is shown.
    @State private var comparing = false
    @State private var original: UIImage?
    @State private var listing = false
    @State private var hangerBusy = false
    @State private var notice: String?

    private var item: BatchItem? { store.items.first { $0.id == id } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                let size = item?.pixelSize ?? CGSize(width: 4, height: 3)
                let aspect = size.width / max(size.height, 1)
                let w = min(geo.size.width - 24, (geo.size.height - 12) * aspect)
                let h = w / aspect
                ZStack {
                    if item?.removed == true, store.transparent, !comparing { Checker() }
                    if comparing, let original {
                        Image(uiImage: original).resizable().interpolation(.high)
                    } else if let shown = (detailVersion == store.lookVersion ? detail : nil) ?? image {
                        Image(uiImage: shown).resizable().interpolation(.high)
                    } else { ProgressView() }
                }
                .frame(width: w, height: h)
                .scaleEffect(zoom)
                .offset(pan)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .contentShape(Rectangle())
                .gesture(viewGesture)
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { v in
                        let z = min(8, max(1, zoomBase * v.magnification))
                        // Zoom towards the pinch point, then keep the photo filling the view.
                        let k = z / zoom
                        let px = v.startLocation.x - geo.size.width / 2, py = v.startLocation.y - geo.size.height / 2
                        pan = clamped(CGSize(width: px - (px - pan.width) * k, height: py - (py - pan.height) * k), zoom: z)
                        zoom = z
                    }
                    .onEnded { _ in
                        zoomBase = zoom; panBase = pan
                        if zoom <= 1.01 { withAnimation(.easeOut(duration: 0.15)) { resetZoom() } }
                        if zoom > 1.4 { loadDetail() }
                    })
                .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { resetZoom() } }
                .onAppear { box = CGSize(width: w, height: h); container = geo.size }
                .onChange(of: geo.size) { _, g in container = g; box = CGSize(width: w, height: h) }
                .onChange(of: id) { _, _ in box = CGSize(width: w, height: h) }
            }
            .clipped()
            controls.padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .task(id: "\(id)-\(store.lookVersion)-\(item?.removed ?? false)") {
            if let img = await store.renderPreview(id), !Task.isCancelled { image = img }
            if zoom > 1.4 { loadDetail() }
        }
        .fullScreenCover(item: $tool) { t in ToolScreen(tool: t, startID: id) }
        .background(Color.clear.fullScreenCover(isPresented: $touchUp) { TouchUpScreen(id: id) })
        #if PERSONAL
        .sheet(isPresented: $listing) { ListingScreen(id: id) }
        #endif
        .alert("Clearcut", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button("Done") { dismiss() }.font(.system(size: 17, weight: .semibold))
            Spacer()
            if let next = nextToCheck {
                Button("Next to check") { show(next) }.font(.system(size: 16, weight: .medium))
                Spacer()
            }
            Button(role: .destructive) { store.delete(id); dismiss() } label: {
                Image(systemName: "trash").font(.system(size: 17))
            }
            .accessibilityLabel("Remove from batch")
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var controls: some View {
        if let item {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    if let note = item.statusNote {
                        Text(note).font(.system(size: 15)).foregroundStyle(Theme.warning).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    if item.removed && item.canRemove { compareButton }
                }
                if item.canRemove {
                    HStack(spacing: 10) {
                        if item.removed {
                            pill("Touch up") { touchUp = true }
                            pill("Background") { tool = .background }
                            pill("Shadow") { tool = .shadow }
                        }
                    }
                    HStack(spacing: 10) {
                        #if PERSONAL
                        pill("Listing") { listing = true }
                        #endif
                        if item.removed {
                            pill(hangerBusy ? "Working" : item.hangerRemoved ? "Put hook back" : "Remove hook") { toggleHanger(item) }
                                .disabled(hangerBusy)
                        }
                    }
                    Button { store.setRemoved(id, !item.removed) } label: {
                        Text(item.removed ? "Use original photo" : "Use cutout")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(item.removed ? Color.white : Theme.ink)
                            .foregroundStyle(item.removed ? Theme.ink : Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(item.removed ? Theme.line : Color.clear))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    /// The next photo after this one (wrapping round) that is flagged for a look.
    private var nextToCheck: UUID? {
        let all = store.items
        guard let i = all.firstIndex(where: { $0.id == id }), all.count > 1 else { return nil }
        for k in 1..<all.count {
            let other = all[(i + k) % all.count]
            if other.needsAttention { return other.id }
        }
        return nil
    }

    private func show(_ next: UUID) {
        image = nil; detail = nil; detailVersion = -1; original = nil; comparing = false
        resetZoom()
        id = next
    }

    private func toggleHanger(_ item: BatchItem) {
        let on = !item.hangerRemoved
        hangerBusy = true
        Task {
            let done = await store.setHangerRemoved(item.id, on)
            hangerBusy = false
            if !done && on {
                notice = "No hanger hook found at the top of this cutout. This only works when the hook sticks up above the item."
            }
        }
    }

    /// Hold to see the original photo in place of the cutout.
    private var compareButton: some View {
        Text(comparing ? "Original" : "Hold to compare")
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(comparing ? Theme.ink : Color.white)
            .foregroundStyle(comparing ? Color.white : Theme.ink)
            .overlay(Capsule().stroke(comparing ? Color.clear : Theme.line))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !comparing { loadOriginal(); comparing = true }
                }
                .onEnded { _ in comparing = false })
            .accessibilityLabel("Show the original photo while held")
    }

    private func loadOriginal() {
        guard original == nil, let u = item?.previewPhotoURL else { return }
        original = UIImage(contentsOfFile: u.path)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Color.white).foregroundStyle(Theme.ink)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var viewGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                guard zoom > 1 else { return }
                pan = clamped(CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height), zoom: zoom)
            }
            .onEnded { _ in panBase = pan }
    }

    private func resetZoom() { zoom = 1; zoomBase = 1; pan = .zero; panBase = .zero }

    /// Limits panning so the photo's edges never pull in past the edges of the view: there is
    /// always photo under every part of the view once zoomed in.
    private func clamped(_ p: CGSize, zoom z: CGFloat) -> CGSize {
        let mx = max(0, (box.width * z - container.width) / 2)
        let my = max(0, (box.height * z - container.height) / 2)
        return CGSize(width: min(mx, max(-mx, p.width)), height: min(my, max(-my, p.height)))
    }

    private func loadDetail() {
        guard !loadingDetail, detailVersion != store.lookVersion else { return }
        loadingDetail = true
        let v = store.lookVersion
        Task {
            let img = await store.renderDetail(id)
            if let img, v == store.lookVersion { detail = img; detailVersion = v }
            loadingDetail = false
        }
    }
}
