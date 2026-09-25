import SwiftUI

/// The photo behind a fixed frame in the spec's proportions. Drag to move the photo, pinch to zoom,
/// double-tap to go back to the auto crop. Everything outside the frame is dimmed; anything inside the frame
/// but past the photo's edge shows white, as it will be printed.
struct CropCanvas: View {
    @Bindable var model: EditorModel

    @State private var gestureStart: CGRect?
    @State private var translation: CGSize = .zero
    @State private var magnification: CGFloat = 1
    @State private var anchor: CGPoint?
    @State private var dragging = false
    @State private var magnifying = false

    private static let inset: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let frame = frameRect(in: proxy.size)
            let crop = model.crop
            let scale = crop.width > 0 ? frame.width / crop.width : 1

            ZStack(alignment: .topLeading) {
                Color.black

                Rectangle()
                    .fill(.white)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)

                Image(uiImage: model.displayImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: model.imageSize.width * scale, height: model.imageSize.height * scale)
                    .offset(x: frame.minX - crop.minX * scale, y: frame.minY - crop.minY * scale)

                FrameMask(frame: frame)
                    .fill(Color.dsMask, style: FillStyle(eoFill: true))

                if let measurement = model.fittedMeasurement {
                    GuideOverlay(model: model, measurement: measurement, frame: frame)
                }

                Rectangle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(frame: frame).simultaneously(with: magnifyGesture(frame: frame)))
            .onTapGesture(count: 2) {
                withAnimation(.snappy) { model.resetToAuto() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photo in the \(model.spec.sizeLabel) frame")
            .accessibilityHint("Drag to move, pinch to zoom, double-tap for the automatic crop.")
            .accessibilityAdjustableAction { direction in
                zoom(by: direction == .increment ? 1.05 : 1 / 1.05)
            }
        }
        .clipped()
    }

    /// The largest frame in the spec's proportions that fits with an inset all round.
    private func frameRect(in size: CGSize) -> CGRect {
        let available = CGSize(width: size.width - Self.inset * 2, height: size.height - Self.inset * 2)
        let aspect = model.effectiveSpec.aspect
        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: max(1, width), height: max(1, height))
    }

    // MARK: Gestures

    private func dragGesture(frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                begin()
                dragging = true
                translation = value.translation
                apply(frame: frame)
            }
            .onEnded { _ in
                dragging = false
                endIfIdle()
            }
    }

    private func magnifyGesture(frame: CGRect) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                begin()
                magnifying = true
                if anchor == nil { anchor = value.startLocation }
                magnification = value.magnification
                apply(frame: frame)
            }
            .onEnded { _ in
                magnifying = false
                endIfIdle()
            }
    }

    private func begin() {
        guard gestureStart == nil else { return }
        gestureStart = model.crop
        translation = .zero
        magnification = 1
        anchor = nil
    }

    private func endIfIdle() {
        guard !dragging, !magnifying else { return }
        gestureStart = nil
    }

    /// Moves the crop so the photo follows the fingers: the point under the pinch stays under it, and the
    /// photo moves with the drag.
    private func apply(frame: CGRect) {
        guard let start = gestureStart, start.width > 0 else { return }
        let startScale = frame.width / start.width
        let zoom = max(0.2, magnification)
        let newScale = startScale * zoom
        let pivot = anchor ?? CGPoint(x: frame.midX, y: frame.midY)
        let pivotInImage = CGPoint(
            x: start.minX + (pivot.x - frame.minX) / startScale,
            y: start.minY + (pivot.y - frame.minY) / startScale
        )
        let origin = CGPoint(
            x: pivotInImage.x - (pivot.x - frame.minX) / newScale - translation.width / newScale,
            y: pivotInImage.y - (pivot.y - frame.minY) / newScale - translation.height / newScale
        )
        model.crop = clamped(CGRect(origin: origin, size: CGSize(width: start.width / zoom, height: start.height / zoom)))
    }

    private func zoom(by factor: CGFloat) {
        let crop = model.crop
        let size = CGSize(width: crop.width / factor, height: crop.height / factor)
        model.crop = clamped(CGRect(x: crop.midX - size.width / 2, y: crop.midY - size.height / 2, width: size.width, height: size.height))
    }

    /// Keeps the crop between a twentieth of the photo and twice its size, with its centre on the photo.
    private func clamped(_ rect: CGRect) -> CGRect {
        let image = model.imageSize
        let longest = max(image.width, image.height)
        let aspect = rect.width / rect.height
        let width = min(max(rect.width, image.width * 0.05), longest * 2)
        let height = width / aspect
        let midX = min(max(rect.midX, 0), image.width)
        let midY = min(max(rect.midY, 0), image.height)
        return CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
    }
}

/// Everything except the frame.
private struct FrameMask: Shape {
    let frame: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(frame)
        return path
    }
}
