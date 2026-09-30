import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision
import os

/// What the background looks like, measured from the pixels outside the person.
nonisolated struct BackgroundStats: Sendable, Equatable {
    /// Average colour, 0–1 per channel.
    var red: Double, green: Double, blue: Double
    /// Spread of brightness across the background (standard deviation, 0–1). Plain walls stay under ~0.06.
    var unevenness: Double

    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    var saturation: Double {
        let high = max(red, green, blue), low = min(red, green, blue)
        return high == 0 ? 0 : (high - low) / high
    }

    /// The closest tone name, on the same scale the model uses.
    var tone: BackgroundTone {
        if unevenness > 0.12 { return .busy }
        if luminance < 0.45 { return .dark }
        if saturation < 0.06 {
            if luminance > 0.9 { return .white }
            if luminance > 0.8 { return .offWhite }
            return .lightGrey
        }
        let isBlue = blue > red && blue > green
        if isBlue { return luminance > 0.6 ? .lightBlue : .blue }
        if red > green * 1.4 && red > blue * 1.4 { return luminance > 0.6 ? .otherLight : .red }
        if red >= blue && green >= blue && saturation < 0.18 && luminance > 0.75 { return .cream }
        return luminance > 0.6 ? .otherLight : .dark
    }

    var isPlain: Bool { unevenness <= 0.08 }
}

/// Separates the person from the background on-device and measures the background.
nonisolated enum Background {
    private static let logger = Logger(subsystem: "liziyue.PassPhoto", category: "Background")
    private static let context = CIContext()

    /// A greyscale mask the size of the image: white where the person is, black elsewhere, soft at the hair.
    @concurrent
    static func personMask(for image: CGImage) async -> CGImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            logger.notice("Person segmentation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }
        let mask = CIImage(cvPixelBuffer: buffer)
        let scaled = mask.transformed(by: CGAffineTransform(
            scaleX: CGFloat(image.width) / mask.extent.width,
            y: CGFloat(image.height) / mask.extent.height
        ))
        return context.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                                     format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
    }

    /// Measures only the pixels the mask is sure are background, so soft hair edges don't count.
    @concurrent
    static func measure(_ image: CGImage, mask: CGImage) async -> BackgroundStats? {
        // Work on a small copy: the average doesn't need every pixel.
        let side = 256
        guard let small = draw(image, width: side, height: side, gray: false),
              let smallMask = draw(mask, width: side, height: side, gray: true) else { return nil }
        var sum = (r: 0.0, g: 0.0, b: 0.0), lum: [Double] = []
        for i in 0..<(side * side) where smallMask[i] < 20 {
            let r = Double(small[i * 4]) / 255, g = Double(small[i * 4 + 1]) / 255, b = Double(small[i * 4 + 2]) / 255
            sum.r += r; sum.g += g; sum.b += b
            lum.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
        }
        // Less than 5% background: nothing meaningful to measure.
        guard lum.count > side * side / 20 else { return nil }
        let n = Double(lum.count)
        let mean = lum.reduce(0, +) / n
        let spread = (lum.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n).squareRoot()
        return BackgroundStats(red: sum.r / n, green: sum.g / n, blue: sum.b / n, unevenness: spread)
    }

    /// Raw bytes of `image` redrawn at the given size: RGBA, or one byte per pixel for a mask.
    private static func draw(_ image: CGImage, width: Int, height: Int, gray: Bool) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * (gray ? 1 : 4))
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * (gray ? 1 : 4),
                space: gray ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? bytes : nil
    }
}
