import SwiftUI

/// One photo, large. Pinch to zoom in and check edges. Keep or drop the cutout, or touch it up.
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

    // Touch-up
    @State private var touching = false
    enum BrushMode: Hashable { case erase, restore, move }
    @State private var mode: BrushMode = .erase
    @State private var brush: CGFloat = 0.012
    @State private var strokes: [BrushStroke] = []
    @State private var current: [CGPoint] = []
    @State private var saving = false

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
                    if item?.removed == true, store.transparent { Checker() }
                    if let image { Image(uiImage: image).resizable() } else { ProgressView() }
                    if touching { strokeOverlay(width: w, height: h) }
                }
                .frame(width: w, height: h)
                .scaleEffect(zoom)
                .offset(pan)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .contentShape(Rectangle())
                .gesture(touching && mode != .move ? AnyGesture(paintGesture(width: w, height: h, geo: geo).map { _ in () }) : AnyGesture(viewGesture.map { _ in () }))
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { v in zoom = min(8, max(1, zoomBase * v.magnification)) }
                    .onEnded { _ in zoomBase = zoom; if zoom <= 1.01 { resetZoom() } })
                .onTapGesture(count: 2) { if !touching { withAnimation(.easeOut(duration: 0.2)) { resetZoom() } } }
            }
            .clipped()
            controls.padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .task(id: "\(store.lookVersion)-\(item?.removed ?? false)") {
            if let img = await store.renderPreview(id), !Task.isCancelled { image = img }
        }
        .fullScreenCover(item: $tool) { t in ToolScreen(tool: t, startID: id) }
    }

    private var topBar: some View {
        HStack {
            if touching {
                Button("Cancel") { strokes = []; touching = false }
                Spacer()
                Text("Touch up").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(saving ? "Saving" : "Apply") {
                    saving = true
                    Task {
                        await store.applyTouchUp(id, strokes: strokes)
                        strokes = []; saving = false; touching = false
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .disabled(strokes.isEmpty || saving)
            } else {
                Button("Done") { dismiss() }.font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(role: .destructive) { store.delete(id); dismiss() } label: {
                    Image(systemName: "trash").font(.system(size: 17))
                }
                .accessibilityLabel("Remove from batch")
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var controls: some View {
        if let item {
            if touching {
                VStack(spacing: 12) {
                    Picker("Brush", selection: $mode) {
                        Text("Erase").tag(BrushMode.erase)
                        Text("Restore").tag(BrushMode.restore)
                        Text("Move").tag(BrushMode.move)
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        Text("Brush").font(.system(size: 15))
                        Slider(value: $brush, in: 0.003...0.04)
                        Button("Undo") { if !strokes.isEmpty { strokes.removeLast() } }.disabled(strokes.isEmpty)
                    }
                    Text(mode == .move ? "Drag to move around. Pinch to zoom." : "Paint over the edge to fix it. Pinch to zoom.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            } else {
                VStack(spacing: 10) {
                    if let note = item.statusNote {
                        Text(note).font(.system(size: 15)).foregroundStyle(Theme.warning).multilineTextAlignment(.center)
                    } else {
                        Text(zoom > 1 ? "Double-tap to fit." : "Pinch to zoom in on the edges.")
                            .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    }
                    if item.canRemove {
                        HStack(spacing: 10) {
                            if item.removed {
                                pill("Touch up") { resetZoom(); touching = true }
                                pill("Background") { tool = .background }
                                pill("Shadow") { tool = .shadow }
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
                pan = CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height)
            }
            .onEnded { _ in panBase = pan }
    }

    /// Converts touches into resolution-independent stroke points.
    private func paintGesture(width w: CGFloat, height h: CGFloat, geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                                // The view is centred in the container, scaled by zoom and moved by pan.
                let cx = geo.size.width / 2 + pan.width, cy = geo.size.height / 2 + pan.height
                let ix = (v.location.x - cx) / zoom + w / 2, iy = (v.location.y - cy) / zoom + h / 2
                current.append(CGPoint(x: ix / w, y: iy / h))
            }
            .onEnded { _ in
                if !current.isEmpty {
                    strokes.append(BrushStroke(points: current, radius: brush / zoom, erase: mode == .erase))
                }
                current = []
            }
    }

    private func strokeOverlay(width w: CGFloat, height h: CGFloat) -> some View {
        Canvas { ctx, _ in
            let L = max(w, h)
            func draw(_ pts: [CGPoint], _ r: CGFloat, _ erase: Bool) {
                guard let first = pts.first else { return }
                var path = Path()
                path.move(to: CGPoint(x: first.x * w, y: first.y * h))
                for p in pts.dropFirst() { path.addLine(to: CGPoint(x: p.x * w, y: p.y * h)) }
                if pts.count == 1 { path.addLine(to: CGPoint(x: first.x * w + 0.1, y: first.y * h)) }
                ctx.stroke(path, with: .color(erase ? Color.red.opacity(0.45) : Color.green.opacity(0.45)),
                           style: StrokeStyle(lineWidth: r * L * 2, lineCap: .round, lineJoin: .round))
            }
            for s in strokes { draw(s.points, s.radius, s.erase) }
            draw(current, brush / zoom, mode == .erase)
        }
        .allowsHitTesting(false)
    }

    private func resetZoom() { zoom = 1; zoomBase = 1; pan = .zero; panBase = .zero }
}
