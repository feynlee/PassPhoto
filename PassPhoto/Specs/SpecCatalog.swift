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

    static func load(from bundle: Bundle) -> [PhotoSpec] {
        let logger = Logger(subsystem: "liziyue.PassPhoto", category: "Specs")
        let files = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var seen = Set<String>()
        var specs: [PhotoSpec] = []
        for file in files {
            do {
                let decoded = try JSONDecoder().decode([PhotoSpec].self, from: Data(contentsOf: file))
                // The first file to define an id wins, so a region's researched file overrides the seed.
                for spec in decoded where seen.insert(spec.id).inserted { specs.append(spec) }
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
