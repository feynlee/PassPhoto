#if DEBUG
import CoreGraphics
import UIKit

/// A drawn stand-in portrait with known measurements, for looking at the editor without a real face.
/// Opened by launching with `-demoEditor`. Debug builds only.
enum DemoPhoto {
    static let size = CGSize(width: 1500, height: 2000)

    static let measurement = FaceMeasurement(
        crownY: 520, skullTopY: 560, chinY: 1180, eyeY: 850, centerX: 760, faceWidth: 470,
        rollDegrees: 1.2, yawDegrees: 0, faceCount: 1, crownIsEstimated: false, source: .vision
    )

    static func image() -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            // A light blue wall: fails "white" rules, so background checks have something to say.
            UIColor(red: 0.80, green: 0.87, blue: 0.93, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.30, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 200, y: 1300, width: 1120, height: 900))
            UIColor(red: 0.80, green: 0.66, blue: 0.58, alpha: 1).setFill()
            cg.fill(CGRect(x: 680, y: 1100, width: 160, height: 260))
            cg.fillEllipse(in: CGRect(x: 525, y: 600, width: 470, height: 580))
            UIColor(red: 0.22, green: 0.16, blue: 0.12, alpha: 1).setFill()
            let hair = UIBezierPath()
            hair.move(to: CGPoint(x: 520, y: 820))
            hair.addQuadCurve(to: CGPoint(x: 760, y: 520), controlPoint: CGPoint(x: 510, y: 520))
            hair.addQuadCurve(to: CGPoint(x: 1000, y: 820), controlPoint: CGPoint(x: 1010, y: 520))
            hair.addQuadCurve(to: CGPoint(x: 760, y: 660), controlPoint: CGPoint(x: 940, y: 650))
            hair.addQuadCurve(to: CGPoint(x: 520, y: 820), controlPoint: CGPoint(x: 580, y: 650))
            hair.fill()
            UIColor(white: 0.15, alpha: 1).setFill()
            for x in [660.0, 860.0] { cg.fillEllipse(in: CGRect(x: x - 22, y: 835, width: 44, height: 30)) }
            UIColor(red: 0.62, green: 0.40, blue: 0.38, alpha: 1).setFill()
            cg.fill(CGRect(x: 705, y: 1050, width: 110, height: 16))
        }.cgImage!
    }
}
#endif
