import Foundation
import Testing
@testable import PassPhoto

struct UpdaterTests {
    private func entry(_ id: String, head: [Double], schema: Int? = nil, verified: String = "2026-10-01") -> [String: Any] {
        var e: [String: Any] = [
            "id": id, "countryCode": "CA", "country": "Canada", "document": "Passport", "kind": "passport",
            "widthMM": 50, "heightMM": 70, "sizeLabel": "50 × 70 mm", "headHeightMM": head,
            "background": "plainLight", "glasses": "allowed", "source": "https://www.canada.ca", "verified": verified,
        ]
        if let schema { e["schema"] = schema }
        return e
    }

    private func write(_ entries: [[String: Any]]) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: entries).write(to: url)
        return url
    }

    @Test func downloadedEntriesOverrideBundledOnes() throws {
        let downloaded = try write([entry("ca-passport", head: [32, 36])])
        let bundled = try write([entry("ca-passport", head: [31, 36], verified: "2026-09-25"), entry("ca-visa", head: [31, 36])])
        let specs = SpecCatalog.load(files: [downloaded, bundled])
        #expect(specs.count == 2)
        #expect(specs.first { $0.id == "ca-passport" }?.headHeightMM == 32...36)
        #expect(specs.first { $0.id == "ca-passport" }?.verified == "2026-10-01")
    }

    @Test func entriesNeedingANewerAppAreSkipped() throws {
        let file = try write([entry("ca-passport", head: [31, 36], schema: PhotoSpec.supportedSchema + 1), entry("ca-visa", head: [31, 36])])
        #expect(SpecCatalog.load(files: [file]).map(\.id) == ["ca-visa"])
    }

    @Test func fingerprintChangesWithTheRules() throws {
        let a = try #require(SpecCatalog.load(files: [try write([entry("ca-passport", head: [31, 36])])]).first)
        let b = try #require(SpecCatalog.load(files: [try write([entry("ca-passport", head: [32, 36], verified: "2027-01-01")])]).first)
        let c = try #require(SpecCatalog.load(files: [try write([entry("ca-passport", head: [31, 36], verified: "2027-01-01")])]).first)
        #expect(a.fingerprint != b.fingerprint)
        // A new "as of" date alone doesn't mean the rules changed.
        #expect(a.fingerprint == c.fingerprint)
    }

    @Test func germanyWarnsThatHomePhotosMayBeRefused() throws {
        let germany = try #require(SpecCatalog.spec(id: "de-passport-id"))
        #expect(germany.applicantPhoto == .certifiedPhotographerOnly)
        #expect(SpecNoticesSection.applicantMessage(germany) != nil)
    }
}

struct VerifiedDateTests {
    @Test func verifiedDateIsTheSameCalendarDayEverywhere() throws {
        let spec = try #require(SpecCatalog.all.first { $0.verified == "2026-09-25" })
        let day = Calendar.current.dateComponents([.year, .month, .day], from: try #require(spec.verifiedDate))
        #expect(day.year == 2026 && day.month == 9 && day.day == 25)
    }
}
