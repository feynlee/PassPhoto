import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

nonisolated enum PhotoRenderer {
    /// Draws `crop` of `image` at the spec's output size. Only scaling happens: any part of the frame past the
    /// photo's edge is white.
    static func render(_ image: CGImage, crop: CGRect, size: CGSize) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let scale = size.width / crop.width
        // Core Graphics has a bottom-left origin; the crop is top-left.
        let drawn = CGRect(
            x: -crop.minX * scale,
            y: size.height - (CGFloat(image.height) - crop.minY) * scale,
            width: CGFloat(image.width) * scale,
            height: CGFloat(image.height) * scale
        )
        context.draw(image, in: drawn)
        return context.makeImage()
    }

    /// JPEG with the print resolution recorded, so print shops size it correctly. With `maxKB`, quality steps
    /// down until the file fits an upload limit.
    static func jpegData(_ image: CGImage, dpi: Double, quality: Double = 0.92, maxKB: Int?) -> Data? {
        guard let maxKB else { return jpegData(image, dpi: dpi, quality: quality) }
        var q = quality
        while q > 0.3 {
            guard let data = jpegData(image, dpi: dpi, quality: q) else { return nil }
            if data.count <= maxKB * 1024 { return data }
            q -= 0.07
        }
        return jpegData(image, dpi: dpi, quality: 0.3)
    }

    static func jpegData(_ image: CGImage, dpi: Double, quality: Double = 0.92) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Redraws a photo upright (camera photos are often stored rotated with an orientation flag) and no larger
    /// than `maxDimension`, so measurements and crops use one coordinate space.
    static func normalized(_ image: UIImage, maxDimension: CGFloat = 4032) -> CGImage? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }
}
