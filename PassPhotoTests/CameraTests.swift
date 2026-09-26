import CoreGraphics
import ImageIO
import Testing
@testable import PassPhoto

struct CameraTests {
    @Test func framesAreReadUprightForEachWayThePhoneIsHeld() {
        // Held upright, the back camera needs a 90° rotation: its frames read as .right.
        #expect(CameraController.orientation(forRotationAngle: 90, front: false) == .right)
        #expect(CameraController.orientation(forRotationAngle: 90, front: true) == .leftMirrored)
        #expect(CameraController.orientation(forRotationAngle: 0, front: false) == .up)
        #expect(CameraController.orientation(forRotationAngle: 180, front: false) == .down)
        #expect(CameraController.orientation(forRotationAngle: 270, front: true) == .rightMirrored)
    }

    /// A reading whose face sits exactly on the outline's face target, on a 402 × 874 screen.
    private func centredReading(scale: Double = 1, offsetX: Double = 0) -> FrameReading {
        let screen = CGSize(width: 402, height: 874)
        let target = CaptureHint.faceTarget(in: screen)
        let visibleWidth = min(1, (screen.width / screen.height) / CaptureHint.frameAspect)
        // Back from screen points to the frame's normalized coordinates.
        let width = target.width * scale / screen.width * visibleWidth
        let height = target.height * scale / screen.height
        let midX = ((target.midX + offsetX) / screen.width - 0.5) * visibleWidth + 0.5
        let face = CGRect(x: midX - width / 2, y: target.midY / screen.height - height / 2, width: width, height: height)
        return FrameReading(face: face, faceCount: 1, rollDegrees: 1, yawDegrees: 3, brightness: 0.5)
    }

    @Test func aFaceInTheOutlineIsReady() {
        let screen = CGSize(width: 402, height: 874)
        #expect(CaptureHint(reading: centredReading(), tilt: 1, pitch: 3, screen: screen).ready)
        // Some slack in size and position still counts.
        #expect(CaptureHint(reading: centredReading(scale: 1.2, offsetX: 30), tilt: 3, pitch: 8, screen: screen).ready)
        #expect(CaptureHint(reading: centredReading(scale: 0.5), tilt: 0, pitch: 0, screen: screen).message == "Move closer")
        #expect(CaptureHint(reading: centredReading(scale: 1.8), tilt: 0, pitch: 0, screen: screen).message == "Move back a little")
    }

    @Test func hintsDoNotFlicker() {
        var stabilizer = HintStabilizer()
        let ready = CaptureHint(message: "Looks good — take the photo", ready: true)
        let closer = CaptureHint(message: "Move closer", ready: false)
        // Ready takes three steady readings to show…
        #expect(!stabilizer.update(ready).ready)
        #expect(!stabilizer.update(ready).ready)
        #expect(stabilizer.update(ready).ready)
        // …and one stray reading doesn't take it away.
        #expect(stabilizer.update(closer).ready)
        #expect(stabilizer.update(ready).ready)
    }
}
