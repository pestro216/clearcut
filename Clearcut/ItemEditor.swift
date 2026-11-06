import SwiftUI
import CoreImage

/// Full-screen view of one photo: move and resize the item, or remove/restore its background.
struct ItemEditor: View {
    @EnvironmentObject var store: BatchStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID

    @State private var background: UIImage?
    @State private var foreground: UIImage?
    @State private var original: UIImage?
    @State private var canvas: CGSize = CGSize(width: 1, height: 1)
    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1

    private var item: BatchItem? { store.items.first { $0.id == id } }

    private var renderKey: String {
        guard let item else { return "gone" }
        return "\(store.look.hashValue)|\(item.offset.width)|\(item.offset.height)|\(item.scale)|\(item.removed)|\(store.backdropPhotoID)"
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
                let fitted = fit(canvas, in: CGSize(width: geo.size.width - 32, height: geo.size.height - 16))
                ZStack {
                    if let item, item.removed {
                        if store.look.backdrop == .transparent { Checker() }
                        if let background { Image(uiImage: background).resizable() }
                        if let foreground {
                            Image(uiImage: foreground).resizable()
                                .scaleEffect(pinch, anchor: UnitPoint(x: 0.5 + item.offset.width, y: 0.5 + item.offset.height))
                                .offset(drag)
                        }
                    } else if let original {
                        Image(uiImage: original).resizable()
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        DragGesture()
                            .onChanged { v in if item?.removed == true { drag = v.translation } }
                            .onEnded { v in commit(translation: v.translation, scale: 1, fitted: fitted) },
                        MagnifyGesture()
                            .onChanged { v in if item?.removed == true { pinch = v.magnification } }
                            .onEnded { v in commit(translation: .zero, scale: v.magnification, fitted: fitted) }
                    )
                )
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }

            controls
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .task(id: renderKey) { await render() }
    }

    @ViewBuilder private var controls: some View {
        if let item {
            VStack(spacing: 10) {
                if item.removed {
                    Text("Drag to move. Pinch to resize.")
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
                if item.canRemove {
                    Button {
                        store.update(id) { $0.removed.toggle() }
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
                if item.removed && (item.offset != .zero || item.scale != 1) {
                    Button("Reset position") {
                        store.update(id) { $0.offset = .zero; $0.scale = 1 }
                    }
                    .font(.system(size: 16, weight: .medium))
                    .padding(.top, 2)
                }
            }
        }
    }

    private func fit(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let k = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * k, height: size.height * k)
    }

    private func commit(translation: CGSize, scale: CGFloat, fitted: CGSize) {
        guard let item, item.removed, fitted.width > 0 else { drag = .zero; pinch = 1; return }
        let dx = translation.width / fitted.width
        let dy = translation.height / fitted.height
        store.update(id) {
            $0.offset.width = min(0.7, max(-0.7, item.offset.width + dx))
            $0.offset.height = min(0.7, max(-0.7, item.offset.height + dy))
            $0.scale = min(2.5, max(0.15, item.scale * scale))
        }
    }

    private func render() async {
        guard let item else { return }
        if !item.removed {
            let url = item.originalURL
            let box = await Task.detached(priority: .userInitiated) {
                Box(ImageFiles.loadOriented(url, maxPixel: 1600))
            }.value
            if let cg = box.value {
                original = UIImage(cgImage: cg)
                canvas = CGSize(width: cg.width, height: cg.height)
            }
            drag = .zero; pinch = 1
            return
        }
        guard let url = item.cutoutURL else { return }
        let look = store.look, photo = Box(store.backdropPhoto)
        let size = Renderer.canvasSize(look: look, originalSize: item.originalSize, longSide: 1400)
        let place = Renderer.Placement(offset: item.offset, scale: item.scale)
        let result = await Task.detached(priority: .userInitiated) { () -> Box<(UIImage?, UIImage?)> in
            guard let cut = CIImage(contentsOf: url) else { return Box((nil, nil)) }
            let bgCI = Renderer.backdrop(look, photo: photo.value, size: size)
            let fgCI = Renderer.layer(cutout: cut, look: look, place: place, size: size)
            let bg = look.backdrop == .transparent ? nil : Renderer.cgImage(bgCI, size: size).map { UIImage(cgImage: $0) }
            let fg = Renderer.cgImage(fgCI, size: size).map { UIImage(cgImage: $0) }
            return Box((bg, fg))
        }.value
        if Task.isCancelled { return }
        canvas = size
        background = result.value.0
        foreground = result.value.1
        drag = .zero
        pinch = 1
    }
}
