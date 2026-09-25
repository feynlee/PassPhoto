import Foundation
import Testing
@testable import PassPhoto

struct SpecCatalogTests {
    /// Every entry with the required fields loads, and ids are unique across files.
    @Test func loadsEveryCompleteEntry() throws {
        let files = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        var complete = 0
        for file in files {
            let entries = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
            complete += entries.filter { ($0["headHeightMM"] as? [Double])?.count == 2 }.count
        }
        #expect(SpecCatalog.all.count == complete)
        #expect(Set(SpecCatalog.all.map(\.id)).count == SpecCatalog.all.count)
    }

    @Test func everySpecIsUsable() {
        for spec in SpecCatalog.all {
            #expect(spec.widthMM > 0 && spec.heightMM > 0, "\(spec.id)")
            #expect(spec.headHeightMM.upperBound < spec.heightMM, "\(spec.id) head taller than photo")
            #expect(spec.source.scheme == "https", "\(spec.id)")
        }
    }
}
