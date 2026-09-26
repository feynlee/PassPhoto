import CryptoKit
import Foundation
import os

/// The manifest published with the requirement files: what to download and how to verify it.
nonisolated struct RequirementsManifest: Codable, Sendable, Equatable {
    struct File: Codable, Sendable, Equatable {
        let path: String
        let sha256: String
        let bytes: Int
    }

    let schema: Int
    let version: Int
    /// The date of the most recently confirmed document.
    let asOf: String
    let files: [File]
}

/// Keeps the requirements current without an app update. At most once a day it reads the manifest from
/// the public requirements repository; when the version differs from what's installed, it downloads every
/// file, checks each one's SHA-256 against the manifest and that it decodes, and only then replaces the
/// installed copy. Any failure leaves the current requirements in place.
@MainActor
@Observable
final class RequirementsUpdater {
    static let shared = RequirementsUpdater()

    /// Mirrors of github.com/feynlee/passphoto-requirements, tried in order: jsDelivr's CDN, then GitHub.
    static let sources = [
        URL(string: "https://cdn.jsdelivr.net/gh/feynlee/passphoto-requirements@main/")!,
        URL(string: "https://raw.githubusercontent.com/feynlee/passphoto-requirements/main/")!,
    ]
    static let checkInterval: TimeInterval = 24 * 60 * 60

    enum Status: Equatable {
        case idle, checking, updated, upToDate
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// Changes whenever new requirements are installed, so views that list documents refresh.
    private(set) var revision = 0
    private(set) var lastChecked: Date?
    private(set) var installed: RequirementsManifest?

    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "liziyue.PassPhoto", category: "Updater")
    private static let lastCheckedKey = "requirementsLastChecked"

    private init() {
        lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
        installed = try? JSONDecoder().decode(RequirementsManifest.self, from: Data(contentsOf: Self.manifestURL))
    }

    /// The date the app's requirements are as of: the newest confirmation among the documents it has.
    var asOf: Date? {
        SpecCatalog.all.compactMap(\.verifiedDate).max()
    }

    func checkIfDue() async {
        if let lastChecked, Date.now.timeIntervalSince(lastChecked) < Self.checkInterval { return }
        await check()
    }

    func check() async {
        guard status != .checking else { return }
        status = .checking
        do {
            let (manifest, base) = try await fetchManifest()
            if manifest.schema > PhotoSpec.supportedSchema {
                logger.notice("Manifest schema \(manifest.schema) is newer than this app; keeping current requirements")
                status = .upToDate
            } else if manifest == installed {
                status = .upToDate
            } else {
                try await install(manifest, from: base)
                installed = manifest
                SpecCatalog.reload()
                revision += 1
                status = .updated
                logger.notice("Installed requirements version \(manifest.version), as of \(manifest.asOf, privacy: .public)")
            }
            lastChecked = .now
            defaults.set(lastChecked, forKey: Self.lastCheckedKey)
        } catch {
            logger.error("Requirements update failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Download

    enum UpdateError: LocalizedError {
        case unreachable
        case checksum(String)
        case noValidEntries(String)

        var errorDescription: String? {
            switch self {
            case .unreachable: String(localized: "The requirements couldn’t be reached.")
            case .checksum(let path): String(localized: "\(path) didn’t match its checksum.")
            case .noValidEntries(let path): String(localized: "\(path) had no usable requirements.")
            }
        }
    }

    private static var manifestURL: URL { SpecCatalog.downloadedDirectory.appending(path: "manifest.json") }

    private func fetchManifest() async throws -> (RequirementsManifest, URL) {
        for base in Self.sources {
            do {
                let data = try await Self.download(base.appending(path: "manifest.json"))
                return (try JSONDecoder().decode(RequirementsManifest.self, from: data), base)
            } catch {
                logger.notice("Manifest from \(base.host() ?? "", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        throw UpdateError.unreachable
    }

    /// Downloads and verifies every file into a staging folder, then swaps it in.
    private func install(_ manifest: RequirementsManifest, from base: URL) async throws {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appending(path: "requirements-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging.appending(path: "requirements"), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        for file in manifest.files {
            // Only plain file names under requirements/ are accepted.
            let name = (file.path as NSString).lastPathComponent
            guard file.path == "requirements/\(name)", name.hasSuffix(".json") else { continue }
            let data = try await downloadVerified(file, preferring: base)
            guard try SpecCatalog.decode(data).contains(where: { if case .success = $0 { true } else { false } }) else {
                throw UpdateError.noValidEntries(file.path)
            }
            try data.write(to: staging.appending(path: file.path))
        }
        try JSONEncoder().encode(manifest).write(to: staging.appending(path: "manifest.json"))

        let target = SpecCatalog.downloadedDirectory
        try? fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(target, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: target)
        }
    }

    /// One file whose checksum matches the manifest. The CDN caches each file of the branch on its own, so
    /// for a while after a change it can serve a new manifest with an old file; then the next source is tried.
    private func downloadVerified(_ file: RequirementsManifest.File, preferring base: URL) async throws -> Data {
        var mismatched = false
        for source in [base] + Self.sources.filter({ $0 != base }) {
            do {
                let data = try await Self.download(source.appending(path: file.path))
                if SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == file.sha256 { return data }
                mismatched = true
                logger.notice("\(file.path, privacy: .public) from \(source.host() ?? "", privacy: .public) is out of date")
            } catch {
                logger.notice("\(file.path, privacy: .public) from \(source.host() ?? "", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        throw mismatched ? UpdateError.checksum(file.path) : UpdateError.unreachable
    }

    nonisolated private static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw UpdateError.unreachable }
        return data
    }
}
