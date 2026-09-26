import CoreGraphics
import Testing
@testable import PassPhoto

struct CameraTests {
    let screen = CGSize(width: 402, height: 874)

    /// The face box the preview layer would report for a face on the outline's target, in screen points.
    private func face(scale: Double = 1, dx: Double = 0, dy: Double = 0) -> CGRect {
        let target = CaptureHint.faceTarget(in: screen)
        let size = CGSize(width: target.width * scale, height: target.height * scale)
        return CGRect(x: target.midX + dx - size.width / 2, y: target.midY + dy - size.height / 2, width: size.width, height: size.height)
    }

    private func hint(_ face: CGRect?, tilt: Double = 0, pitch: Double = 0) -> CaptureHint {
        CaptureHint(face: face, faceCount: face == nil ? 0 : 1, brightness: 0.5, tilt: tilt, pitch: pitch, screen: screen)
    }

    @Test func aFaceInTheOutlineIsReady() {
        #expect(hint(face()).ready)
        // Some slack in size and position still counts.
        #expect(hint(face(scale: 1.2, dx: 30, dy: 40), tilt: 3, pitch: 8).ready)
        #expect(hint(face(scale: 0.8), tilt: 2).ready)
    }

    @Test func eyesAtTheScreenCentreWhenTheCameraIsAtEyeLevel() {
        // Eyes sit about 47% down the head; with the camera level with them they appear mid-frame.
        let oval = CaptureHint.oval(in: screen)
        let eyes = oval.minY + oval.height * 0.47
        #expect(abs(eyes - screen.height / 2) < screen.height * 0.03)
    }

    @Test func hintsSayWhatToDo() {
        #expect(hint(nil).message == "Look at the camera")
        #expect(hint(face(scale: 0.5)).message == "Move closer")
        #expect(hint(face(scale: 2.2)).message == "Move back a little")
        // A selfie at arm's length, bigger than the outline, is fine.
        #expect(hint(face(scale: 1.7)).ready)
        // Face low on screen: the camera is too high, so lower it; and the reverse.
        #expect(hint(face(dy: 150)).message == "Raise the phone a little")
        #expect(hint(face(dy: -150)).message == "Lower the phone a little")
        #expect(hint(face(dx: 120)).message == "Centre your face in the outline")
    }

    @Test func hintsDoNotFlicker() {
        var stabilizer = HintStabilizer()
        let ready = CaptureHint(message: "Looks good — take the photo", ready: true)
        let closer = CaptureHint(message: "Move closer", ready: false)
        #expect(!stabilizer.update(ready).ready)
        #expect(!stabilizer.update(ready).ready)
        #expect(stabilizer.update(ready).ready)
        // One stray reading doesn't take it away.
        #expect(stabilizer.update(closer).ready)
        #expect(stabilizer.update(ready).ready)
    }
}
