import SwiftUI
import AVFoundation
import CoreMotion

/// A camera for photographing a rail of stock one item after another: a frame guide in the
/// listing shape and a level. You press the shutter for each photo. Photos are cut out when you
/// tap Done, not while shooting, so the camera and the cutout engine never compete for memory.
final class RailCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "app.clearcut.camera")
    private let motion = CMMotionManager()

    enum Phase { case starting, running, denied, unavailable }
    @Published var state = Phase.starting
    @Published var shots: [URL] = []
    @Published var lastShot: UIImage?
    /// Side-to-side tilt in degrees when held upright; nil when held flat (shooting from above).
    @Published var roll: Double?
    /// How far from level when held flat, as an offset for the bubble (-1...1 each way).
    @Published var bubble = CGSize.zero
    @Published var flash = false

    /// Photos the batch still has room for.
    var limit = BatchStore.maxPerBatch

    // Camera queue only.
    private var configured = false
    private var capturing = false
    private var taken = 0
    /// Where photos wait until the batch takes them.
    static var folder: URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let u = support.appendingPathComponent("RailShots", isDirectory: true)
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { if ok { self.begin() } else { self.state = .denied } }
            }
        default: state = .denied
        }
    }

    private func begin() {
        startMotion()
        queue.async {
            if !self.configured {
                guard self.configure() else {
                    DispatchQueue.main.async { self.state = .unavailable }
                    return
                }
                self.configured = true
            }
            self.session.startRunning()
            DispatchQueue.main.async { self.state = .running }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        session.commitConfiguration()
        // Set once the camera's format is settled. About 12 megapixels at most: plenty for
        // listings, and kinder on memory than 48. Only sizes the camera lists are used.
        let dims = device.activeFormat.supportedMaxPhotoDimensions
        let small = dims.filter { Int($0.width) * Int($0.height) <= 12_600_000 }
        if let best = small.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) ?? dims.first {
            photoOutput.maxPhotoDimensions = best
        }
        photoOutput.maxPhotoQualityPrioritization = .quality
        if let c = photoOutput.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        }
        return true
    }

    // MARK: Level

    private func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            let g = m.gravity
            if abs(g.z) > 0.8 {
                self.roll = nil
                self.bubble = CGSize(width: max(-1, min(1, g.x * 6)), height: max(-1, min(1, -g.y * 6)))
            } else {
                self.roll = atan2(g.x, -g.y) * 180 / .pi
            }
        }
    }

    // MARK: Taking photos

    func shutter() {
        queue.async {
            guard self.taken < self.limit else { return }
            self.takePhoto()
        }
    }

    /// Camera queue only.
    private func takePhoto() {
        guard !capturing, configured, session.isRunning else { return }
        capturing = true
        let settings = AVCapturePhotoSettings()
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        settings.photoQualityPrioritization = .balanced
        photoOutput.capturePhoto(with: settings, delegate: self)
        DispatchQueue.main.async {
            self.flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.flash = false }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { queue.async { self.capturing = false } }
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        let url = RailCamera.folder.appendingPathComponent("\(UUID().uuidString).heic")
        guard (try? data.write(to: url)) != nil else { return }
        queue.async { self.taken += 1 }
        let thumb = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 160, height: 160))
        DispatchQueue.main.async {
            self.shots.append(url)
            self.lastShot = thumb
        }
    }

    func discardAll() {
        for u in shots { try? FileManager.default.removeItem(at: u) }
        shots = []
    }
}

/// The camera's live picture.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspect
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Full-screen camera for shooting a batch.
struct RailCameraScreen: View {
    @EnvironmentObject var store: BatchStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = RailCamera()
    @State private var confirmCancel = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch camera.state {
            case .denied:
                notice("Clearcut needs the camera. Open Settings, then Clearcut, and turn on Camera.")
            case .unavailable:
                notice("No camera is available on this device.")
            default:
                CameraPreview(session: camera.session).ignoresSafeArea()
                guide
                level
                if camera.flash { Color.white.opacity(0.6).ignoresSafeArea().allowsHitTesting(false) }
            }
            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .statusBarHidden()
        .onAppear {
            camera.limit = store.room
            store.cameraOpen = true
            camera.start()
        }
        .onDisappear {
            camera.stop()
            store.cameraOpen = false
        }
        .confirmationDialog("Discard these photos?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button(camera.shots.count == 1 ? "Discard 1 photo" : "Discard \(camera.shots.count) photos", role: .destructive) {
                camera.discardAll(); dismiss()
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") { if camera.shots.isEmpty { dismiss() } else { confirmCancel = true } }
            Spacer()
            Text(camera.shots.isEmpty ? "" : camera.shots.count == 1 ? "1 photo" : "\(camera.shots.count) photos")
                .font(.system(size: 16, weight: .semibold)).monospacedDigit()
            Spacer()
            Button("Done") {
                let shots = camera.shots
                camera.stop()
                if !shots.isEmpty { store.addFiles(shots) }
                dismiss()
            }
            .font(.system(size: 17, weight: .semibold))
            .disabled(camera.shots.isEmpty)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            Group {
                if let img = camera.lastShot {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.12)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Spacer()
            Button { camera.shutter() } label: {
                Circle().fill(.white).frame(width: 66, height: 66)
                    .overlay(Circle().stroke(.white, lineWidth: 3).padding(-6))
            }
            .accessibilityLabel("Take photo")
            .disabled(camera.state != .running || camera.shots.count >= camera.limit)
            Spacer()
            Color.clear.frame(width: 52, height: 52)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            if camera.shots.count >= camera.limit {
                Text("The batch is full").font(.system(size: 14)).foregroundStyle(.white.opacity(0.85)).offset(y: -40)
            }
        }
    }

    /// A 4:5 frame (the listing shape most sites use) to keep each item the same size.
    private var guide: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.84
            let h = min(geo.size.height * 0.7, w * 5 / 4)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 1.5)
                .frame(width: h * 4 / 5, height: h)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
    }

    /// A line that turns solid when the phone is level side to side, or a bubble when held flat.
    @ViewBuilder private var level: some View {
        if let roll = camera.roll {
            let ok = abs(roll) < 1.5
            Capsule().fill(ok ? Color.white : Color.white.opacity(0.45))
                .frame(width: 90, height: ok ? 3 : 2)
                .rotationEffect(.degrees(-roll))
                .allowsHitTesting(false)
        } else {
            let ok = abs(camera.bubble.width) < 0.15 && abs(camera.bubble.height) < 0.15
            ZStack {
                Circle().stroke(.white.opacity(0.5), lineWidth: 1.5).frame(width: 44, height: 44)
                Circle().fill(ok ? Color.white : Color.white.opacity(0.6)).frame(width: 12, height: 12)
                    .offset(x: camera.bubble.width * 16, y: camera.bubble.height * 16)
            }
            .allowsHitTesting(false)
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text).foregroundStyle(.white).multilineTextAlignment(.center).padding(32)
    }
}
