import AVFoundation
import CoreMotion
import UIKit
import os

/// What the camera sees right now, for the live coaching.
nonisolated struct FrameReading: Sendable, Equatable {
    /// The largest face, in the capture output's metadata coordinates. Convert it to the screen with the
    /// preview layer's `layerRectConverted(fromMetadataOutputRect:)`, which accounts for the sensor's
    /// rotation, the front camera's mirroring and the preview's fill crop.
    var face: CGRect?
    var faceCount: Int
    /// Average brightness, 0–1.
    var brightness: Double
}

/// Runs the capture session off the main thread: preview, a face check on every few frames, and photos.
nonisolated final class CameraController: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureMetadataOutputObjectsDelegate, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "liziyue.PassPhoto.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    /// The camera's own face detector, whose results the preview layer can place exactly on screen.
    private let metadataOutput = AVCaptureMetadataOutput()
    private var faces: [CGRect] = []
    private var facesUpdated = Date.distantPast
    private let logger = Logger(subsystem: "liziyue.PassPhoto", category: "Camera")
    private var input: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    /// Tracks how the phone is held, so frames and photos come out upright.
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var frameIndex = 0
    private var photoHandler: (@Sendable (UIImage?) -> Void)?

    /// Called on the main actor with each reading.
    var onReading: (@MainActor @Sendable (FrameReading) -> Void)?

    static var isAvailable: Bool { AVCaptureDevice.default(for: .video) != nil }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    func start(position: AVCaptureDevice.Position) {
        queue.async { [self] in
            configure(position: position)
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func switchCamera(to position: AVCaptureDevice.Position) {
        queue.async { [self] in configure(position: position) }
    }

    func capture(_ handler: @escaping @Sendable (UIImage?) -> Void) {
        queue.async { [self] in
            photoHandler = handler
            // Rotate the photo to how the phone is held right now, so the face is upright.
            if let connection = photoOutput.connection(with: .video), let angle = rotation?.videoRotationAngleForHorizonLevelCapture,
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configure(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        if let input { session.removeInput(input) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: device), session.canAddInput(newInput) else {
            logger.error("No camera for position \(position.rawValue)")
            return
        }
        session.addInput(newInput)
        input = newInput
        self.position = position
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)

        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
        }
        if !session.outputs.contains(metadataOutput), session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: queue)
        }
        if metadataOutput.availableMetadataObjectTypes.contains(.face) {
            metadataOutput.metadataObjectTypes = [.face]
        }
    }

    // MARK: Frames

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        faces = metadataObjects.compactMap { ($0 as? AVMetadataFaceObject)?.bounds }
        facesUpdated = .now
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameIndex += 1
        // About five readings a second is plenty for coaching.
        guard frameIndex % 6 == 0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Faces not reported for half a second have left the frame.
        let current = Date.now.timeIntervalSince(facesUpdated) < 0.5 ? faces : []
        let reading = FrameReading(
            face: current.max { $0.width * $0.height < $1.width * $1.height },
            faceCount: current.count,
            brightness: Self.brightness(of: buffer)
        )
        if let onReading {
            Task { @MainActor in onReading(reading) }
        }
    }

    /// The mean of a sparse grid of luma samples.
    private static func brightness(of buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0.5 }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, count = 0
        for y in stride(from: 0, to: height, by: max(1, height / 32)) {
            for x in stride(from: 0, to: width, by: max(1, width / 32)) {
                sum += Int(luma[y * rowBytes + x]); count += 1
            }
        }
        return count == 0 ? 0.5 : Double(sum) / Double(count) / 255
    }

    // MARK: Photos

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        var image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        // Safety net: if the photo still arrives landscape while the phone is held upright, turn it upright.
        if let photo = image, let cgImage = photo.cgImage, photo.size.width > photo.size.height,
           let angle = rotation?.videoRotationAngleForHorizonLevelCapture, Int(angle.rounded()) % 180 == 90 {
            let orientation: UIImage.Orientation = position == .front ? .leftMirrored : .right
            image = UIImage(cgImage: cgImage, scale: photo.scale, orientation: orientation)
        }
        if let error { logger.error("Capture failed: \(error.localizedDescription, privacy: .public)") }
        photoHandler?(image)
        photoHandler = nil
    }
}

/// Tracks how the phone is held, so the photo isn't taken from above or below.
@Observable
final class DeviceLevel {
    /// Sideways tilt and forward/back tilt from upright, in degrees.
    private(set) var tilt: Double = 0
    private(set) var pitch: Double = 0
    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 20
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let gravity = data?.gravity else { return }
            tilt = atan2(gravity.x, -gravity.y) * 180 / .pi
            pitch = atan2(gravity.z, -gravity.y) * 180 / .pi
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}
