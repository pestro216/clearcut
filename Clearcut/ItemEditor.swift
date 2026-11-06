import SwiftUI
import CoreImage

/// One photo, large. Pinch to zoom in and check the edges, double-tap to fit.
/// Remove or restore this photo's background, or take it out of the batch.
struct ItemEditor: View {
    @EnvironmentObject var store: BatchStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID

    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var tool: Tool?

    private var item: BatchItem? { store.items.first { $0.id == id } }

    private var renderKey: String {
        guard let item else { return "gone" }
        return "\(store.look.hashValue)|\(item.removed)|\(store.backdropPhotoID)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(role: .destructive) {
                    store.delete(id)
                    dismiss()
                } label: {
                    Image(systemName: "trash").font(.system(size: 17))
                }
                .accessibilityLabel("Remove from batch")
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            GeometryReader { geo in
                let size = item?.pixelSize ?? CGSize(width: 1, height: 1)
                let aspect = size.width / max(size.height, 1)
                let w = min(geo.size.width - 24, (geo.size.height - 12) * aspect)
                let h = w / aspect
                ZStack {
                    if let item, item.removed, store.look.backdrop == .transparent { Checker() }
                    if let image {
                        Image(uiImage: image).resizable()
                    } else if let o = item?.smallOriginal {
                        Image(uiImage: UIImage(cgImage: o)).resizable().opacity(0.5)
                        ProgressView()
                    }
                }
                .frame(width: w, height: h)
                .scaleEffect(zoom)
                .offset(pan)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { v in zoom = min(8, max(1, zoomBase * v.magnification)) }
                            .onEnded { _ in zoomBase = zoom; if zoom <= 1.01 { resetZoom() } },
                        DragGesture()
                            .onChanged { v in
                                guard zoom > 1 else { return }
                                pan = CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height)
                            }
                            .onEnded { _ in panBase = pan }
                    )
                )
                .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { resetZoom() } }
            }
            .clipped()

            controls
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .task(id: renderKey) { await render() }
        .fullScreenCover(item: $tool) { t in
            ToolScreen(tool: t, startID: id)
        }
    }

    @ViewBuilder private var controls: some View {
        if let item {
            VStack(spacing: 10) {
                Text(zoom > 1 ? "Double-tap to fit." : "Pinch to zoom in and check the edges.")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
                if item.canRemove {
                    if item.removed {
                        HStack(spacing: 10) {
                            pill("Background") { tool = .background }
                            pill("Shadow") { tool = .shadow }
                        }
                    }
                    Button {
                        store.setRemoved(id, !item.removed)
                    } label: {
                        Text(item.removed ? "Restore background" : "Remove background")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(item.removed ? Color.white : Theme.ink)
                            .foregroundStyle(item.removed ? Theme.ink : Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(item.removed ? Theme.line : Color.clear))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                } else {
                    Text("Clearcut couldn't find an item in this photo, so it will be saved as it is.")
                        .font(.system(size: 15)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.white)
                .foregroundStyle(Theme.ink)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func resetZoom() {
        zoom = 1; zoomBase = 1; pan = .zero; panBase = .zero
    }

    /// Renders this photo at up to 2400px so the edges can be inspected closely.
    private func render() async {
        guard let item else { return }
        let url = item.originalURL
        if !item.removed || item.maskURL == nil {
            let box = await Task.detached(priority: .userInitiated) {
                Box(ImageFiles.loadOriented(url, maxPixel: 2400))
            }.value
            if Task.isCancelled { return }
            image = box.value.map { UIImage(cgImage: $0) }
            return
        }
        guard let maskURL = item.maskURL else { return }
        let look = store.look, photo = Box(store.backdropPhoto), bbox = item.bbox
        let result = await Task.detached(priority: .userInitiated) { () -> Box<UIImage?> in
            guard let cg = ImageFiles.loadOriented(url, maxPixel: 2400),
                  let mask = Renderer.maskImage(url: maskURL) else { return Box(nil) }
            let size = CGSize(width: cg.width, height: cg.height)
            let ci = Renderer.compose(original: CIImage(cgImage: cg), mask: mask, bbox: bbox,
                                      look: look, photo: photo.value, size: size)
            return Box(Renderer.cgImage(ci, size: size).map { UIImage(cgImage: $0) })
        }.value
        if Task.isCancelled { return }
        image = result.value
    }
}
