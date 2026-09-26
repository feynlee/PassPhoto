import AVFoundation
import CoreMotion
import UIKit
import Vision
import os

/// What the camera sees right now, for the live coaching.
nonisolated struct FrameReading: Sendable, Equatable {
    /// The face in the upright frame, normalized with a top-left origin; nil when no face is visible.
    var face: CGRect?
    var faceCount: Int
    var rollDegrees: Double
    var yawDegrees: Double
    /// Average brightness, 0–1.
    var brightness: Double
}

/// Runs the capture session off the main thread: preview, a face check on every few frames, and photos.
nonisolated final class CameraController: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "liziyue.PassPhoto.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
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
        // Frames stay as the sensor delivers them (landscape); Vision is told their orientation instead.
    }

    // MARK: Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameIndex += 1
        // About five checks a second is plenty for coaching.
        guard frameIndex % 6 == 0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest()
        let angle = rotation?.videoRotationAngleForHorizonLevelCapture ?? 90
        let orientation = Self.orientation(forRotationAngle: angle, front: position == .front)
        // With the orientation given, Vision's face box is in upright (and, for the front camera, mirrored
        // like the preview) coordinates, matching what's on screen.
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation).perform([request])
        let faces = request.results ?? []
        let face = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
        let reading = FrameReading(
            face: face.map { CGRect(x: $0.boundingBox.minX, y: 1 - $0.boundingBox.maxY, width: $0.boundingBox.width, height: $0.boundingBox.height) },
            faceCount: faces.count,
            rollDegrees: (face?.roll?.doubleValue ?? 0) * 180 / .pi,
            yawDegrees: (face?.yaw?.doubleValue ?? 0) * 180 / .pi,
            brightness: Self.brightness(of: buffer)
        )
        if let onReading {
            Task { @MainActor in onReading(reading) }
        }
    }

    /// How to read a sensor frame upright, given the rotation the device needs for a level picture.
    static func orientation(forRotationAngle angle: CGFloat, front: Bool) -> CGImagePropertyOrientation {
        switch (Int(angle.rounded()) % 360 + 360) % 360 {
        case 90: front ? .leftMirrored : .right
        case 180: front ? .downMirrored : .down
        case 270: front ? .rightMirrored : .left
        default: front ? .upMirrored : .up
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
