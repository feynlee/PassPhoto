import CoreGraphics
import Foundation

/// Copies of a finished photo tiled at true size on standard photo paper, with cut marks, for printing at
/// a pharmacy or photo kiosk.
nonisolated enum PrintSheet {
    enum Paper: String, CaseIterable, Identifiable, Sendable {
        case fourBySix
        case tenByFifteen

        var id: String { rawValue }

        var label: String {
            switch self {
            case .fourBySix: String(localized: "4 × 6 in")
            case .tenByFifteen: String(localized: "10 × 15 cm")
            }
        }

        var fileLabel: String {
            switch self {
            case .fourBySix: "4x6 in"
            case .tenByFifteen: "10x15 cm"
            }
        }

        /// Landscape, in millimetres.
        var sizeMM: CGSize {
            switch self {
            case .fourBySix: CGSize(width: 152.4, height: 101.6)
            case .tenByFifteen: CGSize(width: 150, height: 100)
            }
        }
    }

    static let dpi: Double = 600
    /// Kept clear at the paper's edge, where printers crop.
    static let marginMM: Double = 4
    static let gapMM: Double = 3

    /// How many copies fit, and in which orientation of the paper.
    static func layout(for spec: PhotoSpec, paper: Paper) -> (columns: Int, rows: Int, paper: CGSize) {
        func fit(_ page: CGSize) -> (Int, Int) {
            let columns = Int((page.width - 2 * marginMM + gapMM) / (spec.widthMM + gapMM))
            let rows = Int((page.height - 2 * marginMM + gapMM) / (spec.heightMM + gapMM))
            return (max(0, columns), max(0, rows))
        }
        let landscape = paper.sizeMM
        let portrait = CGSize(width: landscape.height, height: landscape.width)
        let (lc, lr) = fit(landscape), (pc, pr) = fit(portrait)
        return lc * lr >= pc * pr ? (lc, lr, landscape) : (pc, pr, portrait)
    }

    static func copies(for spec: PhotoSpec, paper: Paper) -> Int {
        let layout = layout(for: spec, paper: paper)
        return layout.columns * layout.rows
    }

    static func render(_ photo: CGImage, spec: PhotoSpec, paper: Paper) -> CGImage? {
        let layout = layout(for: spec, paper: paper)
        guard layout.columns > 0, layout.rows > 0 else { return nil }
        let px = dpi / 25.4
        let width = Int((layout.paper.width * px).rounded()), height = Int((layout.paper.height * px).rounded())
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        // Centre the block of photos on the page.
        let blockW = Double(layout.columns) * spec.widthMM + Double(layout.columns - 1) * gapMM
        let blockH = Double(layout.rows) * spec.heightMM + Double(layout.rows - 1) * gapMM
        let left = (layout.paper.width - blockW) / 2
        let top = (layout.paper.height - blockH) / 2

        context.setStrokeColor(CGColor(gray: 0.55, alpha: 1))
        context.setLineWidth(0.15 * px)
        let mark = 1.2 * px
        for row in 0..<layout.rows {
            for column in 0..<layout.columns {
                let x = (left + Double(column) * (spec.widthMM + gapMM)) * px
                // Core Graphics counts up from the bottom.
                let y = Double(height) - (top + Double(row) * (spec.heightMM + gapMM) + spec.heightMM) * px
                let rect = CGRect(x: x, y: y, width: spec.widthMM * px, height: spec.heightMM * px)
                context.draw(photo, in: rect)
                // Cut marks just outside each corner, inside the gap.
                for (cx, dx) in [(rect.minX, -1.0), (rect.maxX, 1.0)] {
                    for (cy, dy) in [(rect.minY, -1.0), (rect.maxY, 1.0)] {
                        context.move(to: CGPoint(x: cx + dx * 0.3 * px, y: cy)); context.addLine(to: CGPoint(x: cx + dx * mark, y: cy))
                        context.move(to: CGPoint(x: cx, y: cy + dy * 0.3 * px)); context.addLine(to: CGPoint(x: cx, y: cy + dy * mark))
                    }
                }
            }
        }
        context.strokePath()
        return context.makeImage()
    }
}
