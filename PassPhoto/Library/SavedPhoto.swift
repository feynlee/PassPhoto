import CoreGraphics
import Foundation
import SwiftData

/// A finished photo kept in the app. The JPEG and the original it was cropped from live in Application
/// Support; the crop is kept so the photo can be adjusted again later.
@Model
final class SavedPhoto {
    var id: UUID = UUID()
    var name: String = ""
    var specID: String = ""
    var createdAt: Date = Date()
    var fileName: String = ""
    var originalFileName: String = ""
    var cropX: Double = 0
    var cropY: Double = 0
    var cropWidth: Double = 0
    var cropHeight: Double = 0
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    /// How many checks needed a look or failed when it was saved.
    var openIssues: Int = 0
    var backgroundReplaced: Bool = false
    var isInfant: Bool = false

    init(name: String, spec: PhotoSpec, createdAt: Date, fileName: String, originalFileName: String, crop: CGRect, pixels: CGSize, openIssues: Int) {
        self.name = name
        self.specID = spec.id
        self.createdAt = createdAt
        self.fileName = fileName
        self.originalFileName = originalFileName
        self.cropX = crop.minX
        self.cropY = crop.minY
        self.cropWidth = crop.width
        self.cropHeight = crop.height
        self.pixelWidth = Int(pixels.width)
        self.pixelHeight = Int(pixels.height)
        self.openIssues = openIssues
    }

    var spec: PhotoSpec { SpecCatalog.spec(id: specID) ?? SpecCatalog.fallback }
    var crop: CGRect { CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight) }
    var fileURL: URL { PhotoStore.directory.appending(path: fileName) }
    var originalURL: URL { PhotoStore.directory.appending(path: originalFileName) }

    /// A clear file name for sharing and the photo library: "US Passport 2026-09-25 14.32.jpg".
    var exportFileName: String { PhotoStore.exportFileName(name: name, date: createdAt) }
}

/// The files behind saved photos.
nonisolated enum PhotoStore {
    static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ data: Data, named name: String) throws {
        try data.write(to: directory.appending(path: name), options: [.atomic, .completeFileProtection])
    }

    static func remove(_ names: [String]) {
        for name in names where !name.isEmpty {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    /// The default name for a new photo: "United States Passport · Sep 25, 2026".
    static func defaultName(for spec: PhotoSpec, date: Date) -> String {
        "\(spec.title) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    static func exportFileName(name: String, date: Date, suffix: String? = nil) -> String {
        let title = name.components(separatedBy: " · ").first ?? name
        let safe = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        // Sortable and the same in every locale: 2026-09-25 14.32.
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d %02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
        return "\(safe.isEmpty ? "Photo" : safe) \(stamp)\(suffix.map { " \($0)" } ?? "").jpg"
    }
}
