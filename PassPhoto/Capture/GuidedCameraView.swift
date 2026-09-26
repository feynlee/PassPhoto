import AVFoundation
import SwiftUI

/// A camera that coaches while framing: an outline to put the head in, and one hint at a time about
/// distance, centring, light and how the phone is held. The shutter works at any time; the outline turns
/// solid blue when everything looks right. Head angle is checked after the photo is taken.
struct GuidedCameraView: View {
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var level = DeviceLevel()
    @State private var reading: FrameReading?
    @State private var stabilizer = HintStabilizer()
    @State private var position: AVCaptureDevice.Position = .back
    @State private var denied = false
    @State private var capturing = false
    @State private var screen = CGSize(width: 390, height: 844)
    @State private var preview = PreviewLayerReference()
    #if DEBUG
    /// Where the camera thinks the face is, drawn in debug builds to check the coaching.
    @State private var debugFace: CGRect?
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if denied {
                ContentUnavailableView {
                    Label("Camera Access Is Off", systemImage: "camera.fill")
                } description: {
                    Text("Allow camera access for PassPhoto in Settings, or choose a photo from your library instead.")
                } actions: {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                .foregroundStyle(.white)
            } else {
                CameraPreview(session: camera.session, reference: preview)
                    .ignoresSafeArea()
                    // The preview and outline fill the whole screen, so measure it, not the safe area.
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
                HeadOutline(ready: hint.ready)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                #if DEBUG
                if let debugFace {
                    Rectangle()
                        .stroke(.yellow, lineWidth: 1.5)
                        .frame(width: debugFace.width, height: debugFace.height)
                        .position(x: debugFace.midX, y: debugFace.midY)
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
                #endif
            }

            VStack {
                HStack {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .padding(12)
                        .background(.black.opacity(0.4), in: .circle)
                    Spacer()
                }
                .padding(.horizontal)

                if !denied {
                    HStack(spacing: 8) {
                        if hint.ready {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.dsGuidePass)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(hint.message)
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background((hint.ready ? Color.dsTintFill : Color.black.opacity(0.6)), in: .capsule)
                    .overlay { Capsule().strokeBorder(Color.dsGuidePass, lineWidth: hint.ready ? 1.5 : 0) }
                    .animation(.snappy, value: hint)
                    .accessibilityAddTraits(.updatesFrequently)
                    // A tap on the hand when everything lines up.
                    .sensoryFeedback(.success, trigger: hint.ready) { _, ready in ready }
                }
                Spacer()

                if !denied {
                    HStack {
                        LevelIndicator(tilt: level.tilt, pitch: level.pitch)
                            .frame(width: 64)
                        Spacer()
                        Button {
                            shoot()
                        } label: {
                            ZStack {
                                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                                Circle().fill(hint.ready ? Color.dsGuidePass : .white).frame(width: 62, height: 62)
                            }
                        }
                        .disabled(capturing)
                        .accessibilityLabel("Take Photo")
                        Spacer()
                        Button("Switch Camera", systemImage: "arrow.triangle.2.circlepath.camera") {
                            position = position == .back ? .front : .back
                            camera.switchCamera(to: position)
                        }
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .frame(width: 64)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
            }
        }
        .task {
            guard await CameraController.requestAccess() else {
                denied = true
                return
            }
            camera.onReading = { newReading in
                reading = newReading
                // The preview layer places the face exactly where it's drawn on screen.
                let face = newReading.face.flatMap { preview.layer?.layerRectConverted(fromMetadataOutputRect: $0) }
                #if DEBUG
                debugFace = face
                #endif
                _ = stabilizer.update(CaptureHint(face: face, faceCount: newReading.faceCount, brightness: newReading.brightness,
                                                  tilt: level.tilt, pitch: level.pitch, screen: screen))
            }
            camera.start(position: position)
            level.start()
        }
        .onDisappear {
            camera.stop()
            level.stop()
        }
        .statusBarHidden()
    }

    private var hint: CaptureHint { stabilizer.shown }

    private func shoot() {
        capturing = true
        camera.capture { image in
            Task { @MainActor in
                capturing = false
                if let image {
                    onCapture(image)
                    dismiss()
                }
            }
        }
    }
}

/// Keeps the coaching steady: a new hint shows only once it has held for a couple of readings, and the
/// ready state takes (and leaves) a little longer, so small wobbles don't make it flicker.
struct HintStabilizer {
    private(set) var shown = CaptureHint(message: String(localized: "Starting the camera…"), ready: false)
    private var pending: CaptureHint?
    private var count = 0

    mutating func update(_ new: CaptureHint) -> CaptureHint {
        if new.message == pending?.message { count += 1 } else { pending = new; count = 1 }
        let needed = (new.ready || shown.ready) ? 3 : 2
        if new.message == shown.message || count >= needed { shown = new }
        return shown
    }
}

/// The one thing to fix next, in priority order.
struct CaptureHint: Equatable {
    let message: String
    let ready: Bool

    /// The head outline, in screen points: head-shaped (a little under three quarters as wide as tall), a
    /// bit over a third of the screen's height, and placed so the eyes (about halfway down the head) land
    /// near the middle of the screen. The preview shows the whole height of the frame, so that's where the
    /// eyes appear when the camera is level with them, which is what passport photos need.
    static func oval(in size: CGSize) -> CGRect {
        let height = size.height * 0.36
        let width = height * 0.74
        return CGRect(x: (size.width - width) / 2, y: size.height * 0.48 - height * 0.47, width: width, height: height)
    }

    /// Where the camera's face box (brows to chin) sits when the head fills the outline.
    static func faceTarget(in size: CGSize) -> CGRect {
        let oval = oval(in: size)
        let height = oval.height * 0.6
        let width = oval.width * 0.82
        return CGRect(x: oval.midX - width / 2, y: oval.minY + oval.height * 0.66 - height / 2, width: width, height: height)
    }

    init(message: String, ready: Bool) {
        self.message = message
        self.ready = ready
    }

    /// - Parameter face: the face in screen points, from the preview layer.
    init(face: CGRect?, faceCount: Int, brightness: Double, tilt: Double, pitch: Double, screen: CGSize) {
        let target = Self.faceTarget(in: screen)
        func hint(_ message: String) -> (String, Bool) { (message, false) }
        let result: (String, Bool) = {
            guard let face else { return hint(String(localized: "Look at the camera")) }
            if faceCount > 1 { return hint(String(localized: "Only one person in the photo")) }
            if brightness < 0.25 { return hint(String(localized: "Find more light")) }
            // Generous limits: PassPhoto crops afterwards, so the framing only has to be roughly right.
            if abs(tilt) > 6 { return hint(String(localized: "Hold the phone straight")) }
            if abs(pitch) > 15 { return hint(String(localized: "Hold the phone upright, at eye level")) }
            // Wide on the large side: at arm's length a selfie's face is bigger than the outline, and
            // cropping takes care of the size.
            if face.height < target.height * 0.65 { return hint(String(localized: "Move closer")) }
            if face.height > target.height * 1.9 { return hint(String(localized: "Move back a little")) }
            // Say which way, so it's clear what to do.
            let dx = face.midX - target.midX, dy = face.midY - target.midY
            if abs(dy) > screen.height * 0.08 { return hint(dy > 0 ? String(localized: "Raise the phone a little") : String(localized: "Lower the phone a little")) }
            if abs(dx) > screen.width * 0.12 { return hint(String(localized: "Centre your face in the outline")) }
            return (String(localized: "Looks good — take the photo"), true)
        }()
        message = result.0
        ready = result.1
    }
}

/// A head-shaped outline where the head should go.
private struct HeadOutline: View {
    let ready: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let oval = CaptureHint.oval(in: size)
            let color = ready ? Color.dsGuidePass : .white
            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addEllipse(in: oval)
                }
                .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                Path { $0.addEllipse(in: oval) }
                    .stroke(color, style: StrokeStyle(lineWidth: 3, dash: ready ? [] : [10, 8]))
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
    }
}

/// A bubble level: centred when the phone is upright and square.
private struct LevelIndicator: View {
    let tilt: Double
    let pitch: Double

    var body: some View {
        let isLevel = abs(tilt) <= 4 && abs(pitch) <= 12
        ZStack {
            Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
            Circle()
                .fill(isLevel ? Color.dsGuidePass : Color.dsGuideAttention)
                .frame(width: 12, height: 12)
                .offset(x: max(-20, min(20, tilt)), y: max(-20, min(20, pitch)))
        }
        .frame(width: 48, height: 48)
        .accessibilityElement()
        .accessibilityLabel(isLevel ? String(localized: "Phone is level") : String(localized: "Phone is tilted"))
    }
}

/// Lets the coaching convert camera coordinates with the preview layer that draws them.
final class PreviewLayerReference {
    weak var layer: AVCaptureVideoPreviewLayer?
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let reference: PreviewLayerReference

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        reference.layer = view.previewLayer
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
