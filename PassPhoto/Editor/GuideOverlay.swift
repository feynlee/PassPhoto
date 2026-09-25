import SwiftUI

/// The guides inside the frame: a target oval where auto-crop puts the head, the allowed bands for the eyes
/// and the top of the head, and a bracket measuring the head as it sits now. Guides turn cyan when a
/// measurement is inside its range and orange when it isn't.
struct GuideOverlay: View {
    let model: EditorModel
    let measurement: FaceMeasurement
    let frame: CGRect

    var body: some View {
        Canvas { context, _ in
            let spec = model.effectiveSpec
            let crop = model.crop
            guard crop.width > 0 else { return }
            let scale = frame.width / crop.width
            let perMM = frame.width / spec.widthMM
            func y(_ imageY: Double) -> CGFloat { frame.minY + (imageY - crop.minY) * scale }
            func x(_ imageX: Double) -> CGFloat { frame.minX + (imageX - crop.minX) * scale }

            context.clip(to: Path(frame))

            // Centre line.
            stroke(&context, [CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.midX, y: frame.maxY)],
                   color: .dsGuideNeutral.opacity(0.45), dash: [4, 6], width: 1, halo: false)

            // Target oval, from the auto crop.
            let auto = model.autoCropRect
            if auto.width > 0 {
                let autoScale = frame.width / auto.width
                let top = frame.minY + (measurement.crownY - auto.minY) * autoScale
                let bottom = frame.minY + (measurement.chinY - auto.minY) * autoScale
                let height = bottom - top
                let oval = CGRect(x: frame.midX - height * 0.37, y: top, width: height * 0.74, height: height)
                context.stroke(Path(ellipseIn: oval), with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
                context.stroke(Path(ellipseIn: oval), with: .color(.dsGuideNeutral.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }

            // Allowed bands, fixed to the frame.
            if let eye = spec.eyeLineFromBottomMM {
                band(&context, from: frame.maxY - eye.upperBound * perMM, to: frame.maxY - eye.lowerBound * perMM,
                     status: model.status(of: "eyes"), label: "Eyes")
            }
            if let margin = spec.topMarginMM {
                band(&context, from: frame.minY + margin.lowerBound * perMM, to: frame.minY + margin.upperBound * perMM,
                     status: model.status(of: "top"), label: "Top of head")
            }

            // Measured lines across the face.
            let half = max(measurement.faceWidth * scale * 0.75, 24)
            let cx = x(measurement.centerX)
            let headColor = model.status(of: "head").guideColor
            for line in [measurement.crownY, measurement.chinY] {
                stroke(&context, [CGPoint(x: cx - half, y: y(line)), CGPoint(x: cx + half, y: y(line))], color: headColor, dash: [5, 4], width: 1.5)
            }
            if spec.eyeLineFromBottomMM != nil {
                let eyeColor = model.status(of: "eyes").guideColor
                stroke(&context, [CGPoint(x: cx - half, y: y(measurement.eyeY)), CGPoint(x: cx + half, y: y(measurement.eyeY))], color: eyeColor, dash: [2, 3], width: 1.5)
            }

            // Head bracket on the right, with the allowed range for the top of the head beside it.
            let bracketX = frame.maxX - 16
            let crownY = y(measurement.crownY), chinY = y(measurement.chinY)
            let allowedTop = chinY - spec.headHeightMM.upperBound * perMM
            let allowedBottom = chinY - spec.headHeightMM.lowerBound * perMM
            let allowed = CGRect(x: bracketX - 4, y: allowedTop, width: 8, height: allowedBottom - allowedTop)
            context.fill(Path(roundedRect: allowed, cornerRadius: 4), with: .color(headColor.opacity(0.35)))
            stroke(&context, [CGPoint(x: bracketX, y: crownY), CGPoint(x: bracketX, y: chinY)], color: headColor, width: 2)
            for tick in [crownY, chinY] {
                stroke(&context, [CGPoint(x: bracketX - 6, y: tick), CGPoint(x: bracketX + 6, y: tick)], color: headColor, width: 2)
            }
            if let geometry = model.geometry {
                label(&context, Checks.mm(geometry.headMM), at: CGPoint(x: bracketX - 10, y: (crownY + chinY) / 2), anchor: .trailing, color: headColor)
            }
        }
        .allowsHitTesting(false)
    }

    private func band(_ context: inout GraphicsContext, from top: CGFloat, to bottom: CGFloat, status: CheckStatus, label text: String) {
        let color = status.guideColor
        context.fill(Path(CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)), with: .color(color.opacity(0.14)))
        for edge in [top, bottom] {
            stroke(&context, [CGPoint(x: frame.minX, y: edge), CGPoint(x: frame.maxX, y: edge)], color: color.opacity(0.8), dash: [3, 4], width: 1)
        }
        label(&context, text, at: CGPoint(x: frame.minX + 6, y: (top + bottom) / 2), anchor: .leading, color: color)
    }

    private func stroke(_ context: inout GraphicsContext, _ points: [CGPoint], color: Color, dash: [CGFloat] = [], width: CGFloat, halo: Bool = true) {
        var path = Path()
        path.addLines(points)
        if halo {
            context.stroke(path, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: width + 2, lineCap: .round, dash: dash))
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
    }

    private func label(_ context: inout GraphicsContext, _ text: String, at point: CGPoint, anchor: UnitPoint, color: Color) {
        let resolved = context.resolve(Text(text).font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(color))
        let size = resolved.measure(in: CGSize(width: 200, height: 40))
        let padded = CGSize(width: size.width + 10, height: size.height + 4)
        let origin = CGPoint(x: point.x - anchor.x * padded.width, y: point.y - padded.height / 2)
        context.fill(Path(roundedRect: CGRect(origin: origin, size: padded), cornerRadius: padded.height / 2), with: .color(.black.opacity(0.6)))
        context.draw(resolved, at: CGPoint(x: origin.x + padded.width / 2, y: point.y), anchor: .center)
    }
}
