import Foundation
import Synchronization
import os

/// Every requirement PassPhoto knows: the files bundled with the app, overridden entry by entry by newer
/// files downloaded from the requirements repository (see RequirementsUpdater). Values come from each
/// issuing office's published photo rules; each spec links its source and the date it was confirmed.
nonisolated enum SpecCatalog {
    private static let storage = Mutex<[PhotoSpec]>(loadAll())

    static var all: [PhotoSpec] { storage.withLock { $0 } }

    static var fallback: PhotoSpec { spec(id: "us-passport") ?? all[0] }

    static func spec(id: String) -> PhotoSpec? {
        all.first { $0.id == id }
    }

    /// Specs grouped by country, countries sorted by name.
    static var byCountry: [(country: String, specs: [PhotoSpec])] {
        Dictionary(grouping: all, by: \.country)
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                // The generic standard goes last.
                if lhs.specs[0].countryCode == "XX" { return false }
                if rhs.specs[0].countryCode == "XX" { return true }
                return lhs.country.localizedStandardCompare(rhs.country) == .orderedAscending
            }
    }

    /// Re-reads the bundled and downloaded files, after an update.
    static func reload() {
        let specs = loadAll()
        storage.withLock { $0 = specs }
    }

    /// Where downloaded requirement files live.
    static var downloadedDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Requirements", directoryHint: .isDirectory)
    }

    private static func loadAll() -> [PhotoSpec] {
        let fileManager = FileManager.default
        let downloaded = ((try? fileManager.contentsOfDirectory(at: downloadedDirectory.appending(path: "requirements"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
        let bundled = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let specs = load(files: downloaded.sorted { $0.lastPathComponent < $1.lastPathComponent }
            + bundled.sorted { $0.lastPathComponent < $1.lastPathComponent })
        // The bundled files always have entries; this only matters if the bundle were broken.
        return specs.isEmpty ? load(files: bundled) : specs
    }

    /// One array element that may or may not be a complete spec this app can use.
    private struct Entry: Decodable {
        let result: Result<PhotoSpec, any Error>

        init(from decoder: any Decoder) throws {
            result = Result { try PhotoSpec(from: decoder) }
        }
    }

    /// The specs in `files`. The first file to define an id wins, so downloaded files (listed first)
    /// override bundled ones; entries that don't decode are skipped one at a time.
    static func load(files: [URL]) -> [PhotoSpec] {
        let logger = Logger(subsystem: "liziyue.PassPhoto", category: "Specs")
        var seen = Set<String>()
        var specs: [PhotoSpec] = []
        for file in files {
            do {
                for entry in try decode(Data(contentsOf: file)) {
                    switch entry {
                    case .success(let spec):
                        if seen.insert(spec.id).inserted { specs.append(spec) }
                    case .failure(let error):
                        logger.notice("Skipped an entry in \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                }
            } catch {
                logger.error("Couldn't read \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        let kindOrder = PhotoSpec.Kind.allCases
        return specs.sorted {
            ($0.country, kindOrder.firstIndex(of: $0.kind)!, $0.document) < ($1.country, kindOrder.firstIndex(of: $1.kind)!, $1.document)
        }
    }

    /// Each entry of a requirements file, decoded on its own.
    static func decode(_ data: Data) throws -> [Result<PhotoSpec, any Error>] {
        try JSONDecoder().decode([Entry].self, from: data).map(\.result)
    }
}
