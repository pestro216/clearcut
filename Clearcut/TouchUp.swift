import SwiftUI
import UIKit
import QuartzCore

/// The photo and its matte at touch-up resolution (the same size).
struct TouchUpSource: @unchecked Sendable {
    let photo: RGBAImage
    let image: CGImage
    let alpha: [UInt8]
}

/// Touch-up state: the live matte, the strokes made so far, and the brush settings.
/// Strokes are painted straight into the matte as you draw, so what you see is the result.
@MainActor
final class TouchUpModel: ObservableObject {
    enum Mode { case erase, restore }

    @Published var mode: Mode = .restore
    @Published var smart = true
    /// Brush diameter on screen, in points (the same size whatever the zoom).
    @Published var brushPoints: CGFloat = 34
    @Published var showRemoved = true { didSet { canvas?.updateGhost() } }
    @Published private(set) var strokeCount = 0
    @Published private(set) var redoCount = 0

    let photo: RGBAImage
    let image: CGImage
    let width: Int
    let height: Int
    private let base: [UInt8]
    private(set) var alpha: [UInt8]
    private(set) var strokes: [BrushStroke] = []
    private var redoStack: [BrushStroke] = []
    private var current: BrushStroke?
    private var snapshot: [UInt8]?
    private var lastPoint: CGPoint?
    private var gate: Brush.Gate?
    weak var canvas: TouchUpCanvasView?

    init(source: TouchUpSource) {
        photo = source.photo
        image = source.image
        width = source.photo.width
        height = source.photo.height
        base = source.alpha
        alpha = source.alpha
    }

    var hasEdits: Bool { strokeCount > 0 }
    private var longSide: CGFloat { CGFloat(max(width, height)) }
    private func normalised(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / CGFloat(width), y: p.y / CGFloat(height)) }

    /// Starts a stroke at a point in photo pixels, with a radius in photo pixels.
    func begin(at p: CGPoint, radius r: CGFloat) {
        snapshot = alpha
        let reference = smart ? Brush.sample(photo, at: p, radius: max(2, r * 0.35)) : nil
        let s = BrushStroke(points: [normalised(p)], radius: r / longSide, erase: mode == .erase,
                            reference: reference, tolerance: smart ? Brush.smartTolerance : 0)
        gate = Brush.Gate(photo: photo, stroke: s)
        current = s
        lastPoint = p
        Brush.segment(&alpha, width, height, from: p, to: p, radius: r, erase: s.erase, gate: gate)
        canvas?.maskChanged()
    }

    func extend(to p: CGPoint) {
        guard var s = current, let last = lastPoint else { return }
        let r = s.radius * longSide
        if hypot(p.x - last.x, p.y - last.y) < max(0.5, r * 0.08) { return }
        Brush.segment(&alpha, width, height, from: last, to: p, radius: r, erase: s.erase, gate: gate)
        s.points.append(normalised(p))
        current = s
        lastPoint = p
        canvas?.maskChanged()
    }

    func end() {
        guard let s = current else { return }
        strokes.append(s)
        redoStack.removeAll()
        current = nil; snapshot = nil; lastPoint = nil; gate = nil
        strokeCount = strokes.count; redoCount = 0
    }

    /// Takes back the stroke in progress (a second finger came down to zoom).
    func cancelStroke() {
        guard current != nil else { return }
        if let snapshot { alpha = snapshot }
        current = nil; snapshot = nil; lastPoint = nil; gate = nil
        canvas?.maskChanged()
    }

    func undo() {
        cancelStroke()
        guard let s = strokes.popLast() else { return }
        redoStack.append(s)
        alpha = base
        Brush.apply(strokes, to: &alpha, width: width, height: height, photo: photo)
        strokeCount = strokes.count; redoCount = redoStack.count
        canvas?.maskChanged()
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        strokes.append(s)
        Brush.apply([s], to: &alpha, width: width, height: height, photo: photo)
        strokeCount = strokes.count; redoCount = redoStack.count
        canvas?.maskChanged()
    }

    // MARK: Mask image

    private var maskContext: CGContext?
    private var maskIsAlphaOnly = true

    /// The matte as an image whose alpha is the matte, for use as a layer mask.
    func maskImage() -> CGImage? {
        let w = width, h = height
        if maskContext == nil {
            if let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) {
                maskContext = c; maskIsAlphaOnly = true
            } else {
                maskContext = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: ColourSpaces.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                maskIsAlphaOnly = false
            }
        }
        guard let ctx = maskContext, let data = ctx.data else { return nil }
        let row = ctx.bytesPerRow
        let dst = data.assumingMemoryBound(to: UInt8.self)
        alpha.withUnsafeBufferPointer { src in
            guard let s = src.baseAddress else { return }
            if maskIsAlphaOnly {
                for y in 0..<h { memcpy(dst + y * row, s + y * w, w) }
            } else {
                for y in 0..<h {
                    let d = dst + y * row
                    for x in 0..<w {
                        let a = s[y * w + x]
                        d[x * 4] = a; d[x * 4 + 1] = a; d[x * 4 + 2] = a; d[x * 4 + 3] = a
                    }
                }
            }
        }
        return ctx.makeImage()
    }
}

// MARK: Canvas

/// The touch-up canvas. One finger paints, two fingers pan and zoom (a second finger cancels the
/// stroke it interrupted, so zooming never leaves stray paint), a two-finger tap undoes.
/// The item is shown cut out over a checkerboard, with what has been removed shown faintly,
/// so you can see exactly what is kept and what to bring back. A magnifier shows the spot under
/// your finger.
final class TouchUpCanvasView: UIView, UIGestureRecognizerDelegate {
    let model: TouchUpModel

    private let checker = CALayer()
    private let content = CALayer()
    private let ghost = CALayer()
    private let cut = CALayer()
    private let cutMask = CALayer()
    private let ring = CAShapeLayer()
    private let ringShade = CAShapeLayer()

    private let loupe = UIView()
    private let loupeContent = CALayer()
    private let loupeGhost = CALayer()
    private let loupeCut = CALayer()
    private let loupeMask = CALayer()
    private let loupeRing = CAShapeLayer()
    private let loupeSize: CGFloat = 116

    private var scale: CGFloat = 1
    private var offset: CGPoint = .zero
    private var fitSize: CGSize = .zero
    private var paintTouch: UITouch?
    private var maskDirty = true
    private var link: CADisplayLink?

    init(model: TouchUpModel) {
        self.model = model
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(Theme.paper)
        clipsToBounds = true

        checker.backgroundColor = UIColor(patternImage: TouchUpCanvasView.checkerTile()).cgColor
        layer.addSublayer(checker)

        for l in [ghost, cut, loupeGhost, loupeCut] {
            l.contents = model.image
            l.contentsGravity = .resize
            l.minificationFilter = .trilinear
        }
        ghost.opacity = 0.28
        loupeGhost.opacity = 0.28
        cutMask.contentsGravity = .resize
        loupeMask.contentsGravity = .resize
        cut.mask = cutMask
        loupeCut.mask = loupeMask
        content.addSublayer(ghost)
        content.addSublayer(cut)
        layer.addSublayer(content)

        for (l, w, c) in [(ringShade, CGFloat(3), UIColor.black.withAlphaComponent(0.35)), (ring, CGFloat(1.5), UIColor.white)] {
            l.fillColor = UIColor.clear.cgColor
            l.strokeColor = c.cgColor
            l.lineWidth = w
            l.isHidden = true
            layer.addSublayer(l)
        }

        loupe.frame = CGRect(x: 0, y: 0, width: loupeSize, height: loupeSize)
        loupe.layer.cornerRadius = loupeSize / 2
        loupe.layer.masksToBounds = true
        loupe.layer.borderWidth = 3
        loupe.layer.borderColor = UIColor.white.cgColor
        loupe.backgroundColor = UIColor(patternImage: TouchUpCanvasView.checkerTile())
        loupe.isHidden = true
        loupe.isUserInteractionEnabled = false
        loupeContent.addSublayer(loupeGhost)
        loupeContent.addSublayer(loupeCut)
        loupe.layer.addSublayer(loupeContent)
        loupeRing.fillColor = UIColor.clear.cgColor
        loupeRing.strokeColor = UIColor.white.cgColor
        loupeRing.lineWidth = 1.5
        loupeRing.shadowColor = UIColor.black.cgColor
        loupeRing.shadowOpacity = 0.6
        loupeRing.shadowRadius = 1
        loupeRing.shadowOffset = .zero
        loupe.layer.addSublayer(loupeRing)
        addSubview(loupe)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        let tap = UITapGestureRecognizer(target: self, action: #selector(twoFingerTap(_:)))
        tap.numberOfTouchesRequired = 2
        for g in [pinch, pan, tap] as [UIGestureRecognizer] {
            g.delegate = self
            addGestureRecognizer(g)
        }
        updateGhost()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        if window != nil {
            let l = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
            l.add(to: .main, forMode: .common)
            link = l
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let avail = bounds.insetBy(dx: 12, dy: 12).size
        guard avail.width > 0, avail.height > 0 else { return }
        let aspect = CGFloat(model.width) / CGFloat(max(1, model.height))
        let w = min(avail.width, avail.height * aspect)
        fitSize = CGSize(width: w, height: w / aspect)
        applyTransform(animated: false)
    }

    // MARK: Drawing

    func maskChanged() { maskDirty = true }

    func updateGhost() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ghost.isHidden = !model.showRemoved
        loupeGhost.isHidden = !model.showRemoved
        CATransaction.commit()
    }

    fileprivate func tick() {
        guard maskDirty else { return }
        maskDirty = false
        let img = model.maskImage()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        cutMask.contents = img
        loupeMask.contents = img
        CATransaction.commit()
    }

    private func applyTransform(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(0.22) }
        let rect = CGRect(origin: .zero, size: fitSize)
        for l in [content, ghost, cut, cutMask] { l.bounds = rect }
        ghost.position = CGPoint(x: rect.midX, y: rect.midY)
        cut.position = ghost.position
        cutMask.position = ghost.position
        content.position = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
        content.transform = CATransform3DMakeScale(scale, scale, 1)
        checker.frame = CGRect(x: content.position.x - fitSize.width * scale / 2, y: content.position.y - fitSize.height * scale / 2,
                               width: fitSize.width * scale, height: fitSize.height * scale)
        CATransaction.commit()
    }

    /// Keeps the photo on screen: at fit it is centred, zoomed in its edges never pull inside the view.
    private func clampOffset() {
        let mx = max(0, (fitSize.width * scale - bounds.width) / 2 + 24)
        let my = max(0, (fitSize.height * scale - bounds.height) / 2 + 24)
        offset.x = scale <= 1.001 ? 0 : min(mx, max(-mx, offset.x))
        offset.y = scale <= 1.001 ? 0 : min(my, max(-my, offset.y))
    }

    func fit() {
        scale = 1; offset = .zero
        applyTransform(animated: true)
    }

    // MARK: Coordinates

    /// A point in this view to photo pixels.
    private func photoPoint(_ p: CGPoint) -> CGPoint {
        let local = CGPoint(x: (p.x - bounds.midX - offset.x) / scale + fitSize.width / 2,
                            y: (p.y - bounds.midY - offset.y) / scale + fitSize.height / 2)
        let k = CGFloat(model.width) / max(1, fitSize.width)
        return CGPoint(x: local.x * k, y: local.y * k)
    }

    /// Brush radius in photo pixels for the current zoom.
    private var radiusPixels: CGFloat {
        (model.brushPoints / 2) / scale * CGFloat(model.width) / max(1, fitSize.width)
    }

    // MARK: Painting

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let all = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled } ?? touches
        if all.count > 1 {
            // A second finger: this is a zoom or pan, not paint.
            stopPainting(cancel: true)
            return
        }
        guard paintTouch == nil, let t = touches.first, fitSize.width > 0 else { return }
        paintTouch = t
        let p = t.location(in: self)
        model.begin(at: photoPoint(p), radius: radiusPixels)
        showBrush(at: p)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = paintTouch, touches.contains(t) else { return }
        for c in event?.coalescedTouches(for: t) ?? [t] {
            model.extend(to: photoPoint(c.location(in: self)))
        }
        showBrush(at: t.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = paintTouch, touches.contains(t) else { return }
        stopPainting(cancel: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = paintTouch, touches.contains(t) else { return }
        stopPainting(cancel: true)
    }

    private func stopPainting(cancel: Bool) {
        guard paintTouch != nil else { return }
        paintTouch = nil
        if cancel { model.cancelStroke() } else { model.end() }
        hideBrush()
    }

    private func showBrush(at p: CGPoint) {
        let r = model.brushPoints / 2
        let path = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)).cgPath
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ring.path = path; ringShade.path = path
        ring.isHidden = false; ringShade.isHidden = false

        // The magnifier sits in a top corner, away from the finger.
        let margin: CGFloat = 14
        let leftSide = !(p.x < loupeSize + 2 * margin && p.y < loupeSize + 2 * margin)
        loupe.frame.origin = CGPoint(x: leftSide ? margin : bounds.width - loupeSize - margin, y: margin)
        let mag: CGFloat = 2.2
        let s = scale * mag
        let local = CGPoint(x: (p.x - bounds.midX - offset.x) / scale + fitSize.width / 2,
                            y: (p.y - bounds.midY - offset.y) / scale + fitSize.height / 2)
        let rect = CGRect(origin: .zero, size: fitSize)
        for l in [loupeContent, loupeGhost, loupeCut, loupeMask] { l.bounds = rect }
        loupeGhost.position = CGPoint(x: rect.midX, y: rect.midY)
        loupeCut.position = loupeGhost.position
        loupeMask.position = loupeGhost.position
        loupeContent.transform = CATransform3DMakeScale(s, s, 1)
        loupeContent.position = CGPoint(x: loupeSize / 2 - (local.x - fitSize.width / 2) * s,
                                        y: loupeSize / 2 - (local.y - fitSize.height / 2) * s)
        let lr = r * mag
        loupeRing.path = UIBezierPath(ovalIn: CGRect(x: loupeSize / 2 - lr, y: loupeSize / 2 - lr, width: 2 * lr, height: 2 * lr)).cgPath
        loupe.isHidden = false
        CATransaction.commit()
    }

    private func hideBrush() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ring.isHidden = true; ringShade.isHidden = true
        loupe.isHidden = true
        CATransaction.commit()
    }

    // MARK: Navigation

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        stopPainting(cancel: true)
        let f = g.scale
        g.scale = 1
        let p = g.location(in: self)
        let newScale = min(16, max(0.8, scale * f))
        let k = newScale / scale
        // Zoom about the fingers: the point under them stays under them.
        let c = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
        let nc = CGPoint(x: p.x - (p.x - c.x) * k, y: p.y - (p.y - c.y) * k)
        offset = CGPoint(x: nc.x - bounds.midX, y: nc.y - bounds.midY)
        scale = newScale
        if g.state == .ended || g.state == .cancelled {
            if scale < 1 { scale = 1 }
            clampOffset()
            applyTransform(animated: true)
        } else {
            applyTransform(animated: false)
        }
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        stopPainting(cancel: true)
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        offset.x += t.x; offset.y += t.y
        if g.state == .ended || g.state == .cancelled {
            clampOffset()
            applyTransform(animated: true)
        } else {
            applyTransform(animated: false)
        }
    }

    @objc private func twoFingerTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        model.undo()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private static func checkerTile() -> UIImage {
        let s: CGFloat = 10
        return UIGraphicsImageRenderer(size: CGSize(width: 2 * s, height: 2 * s)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 2 * s, height: 2 * s))
            UIColor(white: 0.9, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            ctx.fill(CGRect(x: s, y: s, width: s, height: s))
        }
    }
}

/// Breaks the retain cycle between a display link and its view.
@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var view: TouchUpCanvasView?
    init(_ view: TouchUpCanvasView) { self.view = view }
    @objc func tick() { view?.tick() }
}

struct TouchUpCanvas: UIViewRepresentable {
    let model: TouchUpModel
    func makeUIView(context: Context) -> TouchUpCanvasView {
        let v = TouchUpCanvasView(model: model)
        model.canvas = v
        return v
    }
    func updateUIView(_ v: TouchUpCanvasView, context: Context) {}
}

// MARK: Screen

/// Full-screen touch-up for one photo.
struct TouchUpScreen: View {
    @EnvironmentObject var store: BatchStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var model: TouchUpModel?
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                TouchUpEditor(model: model, id: id)
            } else {
                VStack(spacing: 16) {
                    HStack {
                        Button("Cancel") { dismiss() }.font(.system(size: 17))
                        Spacer()
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    Spacer()
                    if failed {
                        Text("This photo couldn't be opened for touch-up.")
                            .font(.system(size: 15)).foregroundStyle(Theme.muted)
                    } else {
                        ProgressView()
                    }
                    Spacer()
                }
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .task {
            if let src = await store.touchUpSource(id) { model = TouchUpModel(source: src) } else { failed = true }
        }
    }
}

private struct TouchUpEditor: View {
    @EnvironmentObject var store: BatchStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: TouchUpModel
    let id: UUID
    @State private var saving = false
    @State private var confirmDiscard = false
    @State private var sizing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { if model.hasEdits { confirmDiscard = true } else { dismiss() } }
                    .font(.system(size: 17))
                Spacer()
                Text("Touch up").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(saving ? "Saving" : "Apply") {
                    saving = true
                    Task {
                        await store.applyTouchUp(id, strokes: model.strokes)
                        dismiss()
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .disabled(!model.hasEdits || saving)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ZStack {
                TouchUpCanvas(model: model)
                if sizing {
                    Circle()
                        .stroke(Color.white, lineWidth: 1.5)
                        .background(Circle().fill(Theme.ink.opacity(0.25)))
                        .frame(width: model.brushPoints, height: model.brushPoints)
                        .allowsHitTesting(false)
                }
                if saving {
                    Color.black.opacity(0.08)
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            controls
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .confirmationDialog("Discard this touch-up?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .interactiveDismissDisabled(model.hasEdits)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                modeButton("Erase", icon: "eraser", mode: .erase)
                modeButton("Restore", icon: "paintbrush.pointed", mode: .restore)
            }
            HStack(spacing: 12) {
                Text("Size").font(.system(size: 15)).foregroundStyle(Theme.ink)
                Slider(value: $model.brushPoints, in: 10...110, onEditingChanged: { editing in
                    withAnimation(.easeOut(duration: 0.15)) { sizing = editing }
                })
                .tint(Theme.ink)
                toggle(model.smart ? "Smart edges on" : "Smart edges off", icon: "wand.and.stars", on: model.smart) {
                    model.smart.toggle()
                }
            }
            HStack(spacing: 10) {
                small("Undo", enabled: model.strokeCount > 0) { model.undo() }
                small("Redo", enabled: model.redoCount > 0) { model.redo() }
                small("Fit", enabled: true) { model.canvas?.fit() }
                toggle("Removed", icon: model.showRemoved ? "eye" : "eye.slash", on: model.showRemoved) {
                    model.showRemoved.toggle()
                }
            }
        }
    }

    private func modeButton(_ title: String, icon: String, mode: TouchUpModel.Mode) -> some View {
        let on = model.mode == mode
        return Button {
            if model.mode != mode {
                model.mode = mode
                UISelectionFeedbackGenerator().selectionChanged()
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(on ? Theme.ink : Color.white)
                .foregroundStyle(on ? Color.white : Theme.ink)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Color.clear : Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityAddTraits(on ? AccessibilityTraits.isSelected : [])
    }

    private func toggle(_ title: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 38)
                .background(on ? Theme.ink : Color.white)
                .foregroundStyle(on ? Color.white : Theme.ink)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? Color.clear : Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityLabel(title)
    }

    private func small(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white)
                .foregroundStyle(Theme.ink)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}
