import CoreGraphics
import Foundation

/// How a crop lays the head out on the finished photo, in millimetres of the printed photo.
nonisolated struct CropGeometry: Equatable, Sendable {
    var headMM: Double
    var eyeFromBottomMM: Double
    var topMarginMM: Double
    var faceWidthMM: Double
    /// The face centre's distance from the photo's centre line; positive to the right.
    var centerOffsetMM: Double
    /// The share of the frame that falls outside the original photo (0–1).
    var outsideFraction: Double
    /// Original pixels across the crop.
    var sourcePixelsWide: Double
}

/// Finds the crop that satisfies a spec by only cropping and scaling the original: no rotation, no
/// retouching and no background changes, so the photo stays exactly as taken.
nonisolated enum CropSolver {
    /// How far off-centre the face may sit before it counts against the photo.
    static let centerToleranceMM = 1.0
    /// The least space auto-crop leaves above the head when the spec positions the head by its eyes.
    static let minSpaceAboveHeadMM = 2.0

    static func geometry(of crop: CGRect, measurement m: FaceMeasurement, spec: PhotoSpec, imageSize: CGSize) -> CropGeometry {
        let pxPerMM = crop.width / spec.widthMM
        let inside = crop.intersection(CGRect(origin: .zero, size: imageSize))
        let insideArea = inside.isNull ? 0 : inside.width * inside.height
        return CropGeometry(
            headMM: m.headHeight / pxPerMM,
            eyeFromBottomMM: (crop.maxY - m.eyeY) / pxPerMM,
            topMarginMM: (m.crownY - crop.minY) / pxPerMM,
            faceWidthMM: m.faceWidth / pxPerMM,
            centerOffsetMM: (m.centerX - crop.midX) / pxPerMM,
            // Rounding leaves slivers like 1e-16; anything under a millionth is inside.
            outsideFraction: { let f = 1 - insideArea / (crop.width * crop.height); return f < 1e-6 ? 0 : f }(),
            sourcePixelsWide: crop.width
        )
    }

    /// The crop closest to the middle of every allowed range that stays inside the photo. When no head size
    /// in the allowed range fits, it keeps the head as small as allowed and lets the frame run past the
    /// photo's edge, which the checks then flag.
    static func autoCrop(measurement m: FaceMeasurement, spec: PhotoSpec, imageSize: CGSize) -> CGRect {
        let range = spec.headHeightMM
        let steps = 24
        let sizes = (0...steps)
            .map { range.lowerBound + (range.upperBound - range.lowerBound) * Double($0) / Double(steps) }
            .sorted { abs($0 - range.mid) < abs($1 - range.mid) }

        for headMM in sizes {
            let pxPerMM = m.headHeight / headMM
            let (topRange, preferredTop) = verticalPlacement(m: m, spec: spec, headMM: headMM, pxPerMM: pxPerMM)
            let width = spec.widthMM * pxPerMM
            let height = spec.heightMM * pxPerMM
            let preferredLeft = m.centerX - width / 2
            let tolerance = centerToleranceMM * pxPerMM
            guard
                let tops = topRange.clamped(within: 0, imageSize.height - height),
                let lefts = (preferredLeft - tolerance...preferredLeft + tolerance).clamped(within: 0, imageSize.width - width)
            else { continue }
            return CGRect(x: lefts.clamp(preferredLeft), y: tops.clamp(preferredTop), width: width, height: height)
        }

        let headMM = range.upperBound
        let pxPerMM = m.headHeight / headMM
        let (topRange, preferredTop) = verticalPlacement(m: m, spec: spec, headMM: headMM, pxPerMM: pxPerMM)
        let width = spec.widthMM * pxPerMM
        let height = spec.heightMM * pxPerMM
        // Within the allowed band, lean towards the photo so as little of the frame as possible is outside it.
        let inPhoto = min(max(preferredTop, 0), max(0, imageSize.height - height))
        return CGRect(x: m.centerX - width / 2, y: topRange.clamp(inPhoto), width: width, height: height)
    }

    /// The allowed range for the crop's top edge and the preferred value, in image pixels.
    private static func verticalPlacement(m: FaceMeasurement, spec: PhotoSpec, headMM: Double, pxPerMM: Double) -> (ClosedRange<Double>, Double) {
        let height = spec.heightMM * pxPerMM
        if let eye = spec.eyeLineFromBottomMM {
            // The crop's bottom edge sits the eye-line distance below the eyes. Where the eye band allows the
            // eyes low in the frame, its middle can push the head against the top edge, so keep some space
            // above the head when the band allows it.
            let byEyes = (m.eyeY + eye.lowerBound * pxPerMM - height)...(m.eyeY + eye.upperBound * pxPerMM - height)
            let clearOfTop = m.crownY - minSpaceAboveHeadMM * pxPerMM
            let range = byEyes.clamped(within: -.infinity, clearOfTop) ?? byEyes
            return (range, range.clamp(m.eyeY + eye.mid * pxPerMM - height))
        }
        if let margin = spec.topMarginMM {
            return (
                (m.crownY - margin.upperBound * pxPerMM)...(m.crownY - margin.lowerBound * pxPerMM),
                m.crownY - margin.mid * pxPerMM
            )
        }
        let spare = spec.heightMM - headMM
        return (
            (m.crownY - spare * 0.6 * pxPerMM)...(m.crownY - spare * 0.2 * pxPerMM),
            m.crownY - spare * PhotoSpec.spaceAboveHeadShare * pxPerMM
        )
    }
}

extension ClosedRange where Bound == Double {
    /// This range narrowed to `low...high`, or nil when they don't overlap.
    nonisolated func clamped(within low: Double, _ high: Double) -> ClosedRange<Double>? {
        let lower = Swift.max(lowerBound, low)
        let upper = Swift.min(upperBound, high)
        return lower <= upper ? lower...upper : nil
    }

    nonisolated func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
