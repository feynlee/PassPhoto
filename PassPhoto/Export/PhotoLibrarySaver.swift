import Foundation
import Photos

nonisolated enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case denied

        var errorDescription: String? {
            "PassPhoto can’t add to your photo library. Allow it in Settings › Privacy & Security › Photos."
        }
    }

    /// Adds the JPEG as is, keeping its clear file name. Needs add-only access, never read access.
    static func save(_ data: Data, fileName: String) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = fileName
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
        }
    }
}
