import AVFoundation
import SwiftUI

/// A camera that coaches while framing: an outline to put the head in, and one hint at a time about
/// distance, centring, light, head angle and how the phone is held. The shutter works at any time; the
/// outline turns cyan when everything looks right.
struct GuidedCameraView: View {
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var level = DeviceLevel()
    @State private var reading: FrameReading?
    @State private var position: AVCaptureDevice.Position = .back
    @State private var denied = false
    @State private var capturing = false
    @State private var screen = CGSize(width: 390, height: 844)

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
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                HeadOutline(ready: hint.ready)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
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
                    Text(hint.message)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background((hint.ready ? Color.dsTint : Color.black.opacity(0.6)), in: .capsule)
                        .animation(.snappy, value: hint.message)
                        .accessibilityAddTraits(.updatesFrequently)
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
            camera.onReading = { reading = $0 }
            camera.start(position: position)
            level.start()
        }
        .onDisappear {
            camera.stop()
            level.stop()
        }
        .statusBarHidden()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
    }

    private var hint: CaptureHint {
        CaptureHint(reading: reading, tilt: level.tilt, pitch: level.pitch, screenAspect: screen.width / max(1, screen.height))
    }

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

/// The one thing to fix next, in priority order.
struct CaptureHint {
    let message: String
    let ready: Bool

    /// Where Vision's face box (brows to chin) should sit on screen, top-left origin. About a fifth of the
    /// screen's height leaves room to crop to any spec at full resolution.
    static let target = CGRect(x: 0.31, y: 0.27, width: 0.38, height: 0.22)

    /// Frames are 3:4 portrait; the preview fills the screen, so a taller screen shows only the middle of
    /// each frame's width.
    static let frameAspect = 3.0 / 4.0

    init(reading: FrameReading?, tilt: Double, pitch: Double, screenAspect: Double) {
        let visibleWidth = min(1, screenAspect / Self.frameAspect)
        func hint(_ message: String) -> (String, Bool) { (message, false) }
        let result: (String, Bool) = {
            guard let reading else { return hint("Starting the camera…") }
            guard let frameFace = reading.face else { return hint("Look at the camera") }
            // The face in screen coordinates, to compare with the outline.
            let face = CGRect(
                x: (frameFace.minX - 0.5) / visibleWidth + 0.5, y: frameFace.minY,
                width: frameFace.width / visibleWidth, height: frameFace.height
            )
            if reading.faceCount > 1 { return hint("Only one person in the photo") }
            if reading.brightness < 0.25 { return hint("Find more light") }
            if abs(tilt) > 4 { return hint("Hold the phone straight") }
            if abs(pitch) > 12 { return hint("Hold the phone upright, at eye level") }
            if face.height < Self.target.height * 0.7 { return hint("Move closer") }
            if face.height > Self.target.height * 1.35 { return hint("Move back a little") }
            let dx = face.midX - Self.target.midX, dy = face.midY - Self.target.midY
            if abs(dx) > 0.08 || abs(dy) > 0.08 { return hint("Put the face in the outline") }
            if abs(reading.rollDegrees) > 5 { return hint("Keep the head level") }
            if abs(reading.yawDegrees) > 12 { return hint("Face the camera straight on") }
            return ("Looks good. Take the photo.", true)
        }()
        message = result.0
        ready = result.1
    }
}

/// A head-and-shoulders outline where the face should go.
private struct HeadOutline: View {
    let ready: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let face = CaptureHint.target
            let oval = CGRect(
                x: face.minX * size.width, y: (face.minY - face.height * 0.45) * size.height,
                width: face.width * size.width, height: face.height * 1.5 * size.height
            )
            let color = ready ? Color.dsGuidePass : .white
            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addEllipse(in: oval)
                }
                .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                Ellipse()
                    .stroke(color, style: StrokeStyle(lineWidth: 3, dash: ready ? [] : [10, 8]))
                    .frame(width: oval.width, height: oval.height)
                    .position(x: oval.midX, y: oval.midY)
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
        .accessibilityLabel(isLevel ? "Phone is level" : "Phone is tilted")
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
