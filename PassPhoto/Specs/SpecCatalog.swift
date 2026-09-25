import Foundation
import os

/// Every requirement PassPhoto knows, from the JSON files bundled from Requirements/. Values come from each
/// issuing office's published photo rules; they change from time to time, so each spec links its source and
/// the date it was checked.
nonisolated enum SpecCatalog {
    static let all: [PhotoSpec] = load(from: Bundle.main)

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

    /// One array element that may or may not be a complete spec.
    private struct Entry: Decodable {
        let result: Result<PhotoSpec, any Error>

        init(from decoder: any Decoder) throws {
            result = Result { try PhotoSpec(from: decoder) }
        }
    }

    static func load(from bundle: Bundle) -> [PhotoSpec] {
        let logger = Logger(subsystem: "liziyue.PassPhoto", category: "Specs")
        let files = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var seen = Set<String>()
        var specs: [PhotoSpec] = []
        for file in files {
            do {
                // Entries are decoded one at a time, so one incomplete entry can't hide the rest of its file.
                let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
                for entry in entries {
                    switch entry.result {
                    case .success(let spec):
                        if seen.insert(spec.id).inserted { specs.append(spec) } else {
                            logger.error("Duplicate id \(spec.id, privacy: .public) in \(file.lastPathComponent, privacy: .public)")
                        }
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
}
