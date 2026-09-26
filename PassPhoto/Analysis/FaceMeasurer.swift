import CoreGraphics
import Foundation
import Vision
import os

/// Where the head is in a photo, in the photo's own pixels with a top-left origin.
nonisolated struct FaceMeasurement: Sendable, Equatable {
    enum Source: Sendable { case vision, privateCloud }

    /// The top of the head, hair included.
    var crownY: Double
    /// The top of the skull, estimated from face proportions: for specs that ignore hair volume.
    var skullTopY: Double
    /// The bottom of the chin.
    var chinY: Double
    /// The line through both pupils.
    var eyeY: Double
    /// Halfway between the eyes.
    var centerX: Double
    /// Cheek to cheek, along the jaw line.
    var faceWidth: Double
    /// Head tilt from the eye line: positive when the right side of the photo is lower.
    var rollDegrees: Double
    /// Head turn, when Vision reports it.
    var yawDegrees: Double?
    var faceCount: Int
    /// The crown came from face proportions because the person couldn't be separated from the background.
    var crownIsEstimated: Bool
    var source: Source

    var headHeight: Double { chinY - crownY }

    /// This measurement with the head top the spec measures to.
    func measuredTo(_ top: PhotoSpec.HeadTop) -> FaceMeasurement {
        guard top == .crown else { return self }
        var copy = self
        // The skull can't be above the hair; with flat hair the two coincide.
        copy.crownY = max(skullTopY, crownY)
        copy.crownIsEstimated = true
        return copy
    }
}

nonisolated enum MeasureError: LocalizedError {
    case noFace

    var errorDescription: String? {
        switch self {
        case .noFace: String(localized: "No face was found in this photo.")
        }
    }
}

/// Measures the head on-device with Vision: face landmarks for the chin, eyes and centre line, and person
/// segmentation for the top of the head (face landmarks stop at the eyebrows, but the requirements measure
/// to the top of the hair).
nonisolated enum FaceMeasurer {
    private static let logger = Logger(subsystem: "liziyue.PassPhoto", category: "Measure")

    /// For a typical adult the crown is about this many eye-to-chin distances above the chin.
    static let crownToChinPerEyeToChin = 2.1
    /// The eyes sit about halfway between the top of the skull and the chin.
    static let skullToChinPerEyeToChin = 2.0

    @concurrent
    static func measure(_ image: CGImage, personMask: CGImage?) async throws -> FaceMeasurement {
        let size = CGSize(width: image.width, height: image.height)
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)

        let faceRequest = VNDetectFaceLandmarksRequest()
        try handler.perform([faceRequest])
        let faces = faceRequest.results ?? []
        guard let face = faces.max(by: { $0.boundingBox.area < $1.boundingBox.area }) else { throw MeasureError.noFace }
        // People in the background count only if their face is at least a fifth the size of the main one.
        let faceCount = faces.filter { $0.boundingBox.area > face.boundingBox.area * 0.2 }.count

        let box = CGRect(
            x: face.boundingBox.minX * size.width,
            y: (1 - face.boundingBox.maxY) * size.height,
            width: face.boundingBox.width * size.width,
            height: face.boundingBox.height * size.height
        )
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            (region?.pointsInImage(imageSize: size) ?? []).map { CGPoint(x: $0.x, y: size.height - $0.y) }
        }
        let landmarks = face.landmarks
        let contour = points(landmarks?.faceContour)
        let leftEye = points(landmarks?.leftPupil).first ?? points(landmarks?.leftEye).centroid
        let rightEye = points(landmarks?.rightPupil).first ?? points(landmarks?.rightEye).centroid

        let chinY = contour.map(\.y).max() ?? box.maxY
        let eyes: (CGPoint, CGPoint) = if let leftEye, let rightEye {
            leftEye.x < rightEye.x ? (leftEye, rightEye) : (rightEye, leftEye)
        } else {
            (CGPoint(x: box.minX + box.width * 0.3, y: box.minY + box.height * 0.35),
             CGPoint(x: box.minX + box.width * 0.7, y: box.minY + box.height * 0.35))
        }
        let eyeY = (eyes.0.y + eyes.1.y) / 2
        let centerX = (eyes.0.x + eyes.1.x) / 2
        let roll = atan2(eyes.1.y - eyes.0.y, eyes.1.x - eyes.0.x) * 180 / .pi
        let faceWidth = contour.isEmpty ? box.width : (contour.map(\.x).max()! - contour.map(\.x).min()!)

        let estimatedCrown = chinY - (chinY - eyeY) * crownToChinPerEyeToChin
        var crownY = estimatedCrown
        var crownIsEstimated = true
        if let personMask, let segmented = segmentedCrown(mask: personMask, centerX: centerX, faceWidth: faceWidth) {
            // Accept the segmentation's crown when it's plausible: above the eyebrows, and not so far up that
            // it must be a hat, a raised hand or someone behind.
            let eyeToChin = chinY - eyeY
            if segmented < eyeY - eyeToChin * 0.6, segmented > eyeY - eyeToChin * 2.2 {
                crownY = segmented
                crownIsEstimated = false
            } else {
                logger.notice("Segmented crown \(segmented) rejected; eye \(eyeY), chin \(chinY)")
            }
        }

        return FaceMeasurement(
            crownY: crownY,
            skullTopY: chinY - (chinY - eyeY) * skullToChinPerEyeToChin,
            chinY: chinY,
            eyeY: eyeY,
            centerX: centerX,
            faceWidth: faceWidth,
            rollDegrees: roll,
            yawDegrees: face.yaw.map { $0.doubleValue * 180 / .pi },
            faceCount: faceCount,
            crownIsEstimated: crownIsEstimated,
            source: .vision
        )
    }

    /// The topmost person pixel over the middle half of the face, from a person mask the size of the image.
    private static func segmentedCrown(mask: CGImage, centerX: Double, faceWidth: Double) -> Double? {
        guard mask.bitsPerPixel == 8, let data = mask.dataProvider?.data, let pixels = CFDataGetBytePtr(data) else { return nil }
        let width = mask.width, height = mask.height, rowBytes = mask.bytesPerRow
        let lo = max(0, Int(centerX - faceWidth / 4))
        let hi = min(width - 1, Int(centerX + faceWidth / 4))
        guard lo < hi else { return nil }

        var tops: [Int] = []
        for x in stride(from: lo, through: hi, by: max(1, (hi - lo) / 40)) {
            for y in 0..<height where pixels[y * rowBytes + x] > 127 {
                tops.append(y)
                break
            }
        }
        guard tops.count >= 5 else { return nil }
        // The 10th percentile: the top of the head's curve, ignoring a stray hair or two.
        return Double(tops.sorted()[tops.count / 10])
    }
}

private extension CGRect {
    nonisolated var area: CGFloat { width * height }
}

private extension Array where Element == CGPoint {
    nonisolated var centroid: CGPoint? {
        guard !isEmpty else { return nil }
        let sum = reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(count), y: sum.y / CGFloat(count))
    }
}
