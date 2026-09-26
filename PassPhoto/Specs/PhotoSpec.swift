import CoreGraphics
import Foundation

/// One country's photo requirements for one document, loaded from the JSON files in Requirements/ (see
/// SCHEMA.md there). Head height is measured from the bottom of the chin to the top of the head, hair
/// included; the eye line from the bottom edge of the photo; the top margin from the top of the head to the
/// top edge.
nonisolated struct PhotoSpec: Identifiable, Hashable, Sendable, Decodable {
    enum Kind: String, Sendable, Decodable, CaseIterable {
        case passport, visa, id, residence, license, other

        var label: String {
            switch self {
            case .passport: String(localized: "Passports")
            case .visa: String(localized: "Visas")
            case .id: String(localized: "ID Cards")
            case .residence: String(localized: "Residence")
            case .license: String(localized: "Licenses")
            case .other: String(localized: "Other")
            }
        }
    }

    enum Background: String, Sendable, Decodable {
        case white, whiteOrOffWhite, creamOrLightGrey, lightGrey, plainLight, lightNotWhite, lightBlue, blue, red

        var requirement: String {
            switch self {
            case .white: String(localized: "Plain white")
            case .whiteOrOffWhite: String(localized: "Plain white or off-white")
            case .creamOrLightGrey: String(localized: "Plain cream or light grey")
            case .lightGrey: String(localized: "Plain light grey")
            case .plainLight: String(localized: "Plain and light-coloured")
            case .lightNotWhite: String(localized: "Plain light colour, not white")
            case .lightBlue: String(localized: "Plain light blue")
            case .blue: String(localized: "Plain blue")
            case .red: String(localized: "Plain red")
            }
        }
    }

    enum Glasses: String, Sendable, Decodable {
        case notAllowed, discouraged, allowed

        var requirement: String {
            switch self {
            case .notAllowed: String(localized: "Glasses aren’t allowed")
            case .discouraged: String(localized: "Remove glasses if you can")
            case .allowed: String(localized: "Glasses allowed without glare or tint")
            }
        }
    }

    /// Where head height is measured to.
    enum HeadTop: String, Sendable, Decodable {
        /// The top of the hair (most countries).
        case hair
        /// The top of the skull, ignoring hair volume (the UK, Switzerland).
        case crown
    }

    /// Whether the issuer accepts a photo the applicant supplies.
    enum ApplicantPhoto: String, Sendable, Decodable {
        case accepted, certifiedPhotographerOnly, officeOnly
    }

    enum Confidence: String, Sendable, Decodable {
        case confirmed, partial
    }

    /// Rules for babies, only where the issuer states different ones.
    struct Infant: Sendable, Decodable, Hashable {
        var maxAgeMonths: Int?
        var eyesMayBeClosed: Bool
        var mouthMayBeOpen: Bool
        var headHeightMM: ClosedRange<Double>?
        var notes: [String]

        private enum CodingKeys: String, CodingKey { case maxAgeMonths, eyesMayBeClosed, mouthMayBeOpen, headHeightMM, notes }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            maxAgeMonths = try c.decodeIfPresent(Int.self, forKey: .maxAgeMonths)
            eyesMayBeClosed = try c.decodeIfPresent(Bool.self, forKey: .eyesMayBeClosed) ?? false
            mouthMayBeOpen = try c.decodeIfPresent(Bool.self, forKey: .mouthMayBeOpen) ?? false
            headHeightMM = try c.decodeRange(.headHeightMM)
            notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        }
    }

    let id: String
    let countryCode: String
    let country: String
    let document: String
    let kind: Kind
    let widthMM: Double
    let heightMM: Double
    /// How the size is written where it's issued: "2 × 2 in", "35 × 45 mm".
    let sizeLabel: String
    private(set) var headHeightMM: ClosedRange<Double>
    let headTop: HeadTop
    let eyeLineFromBottomMM: ClosedRange<Double>?
    let topMarginMM: ClosedRange<Double>?
    /// Cheek to cheek, where the spec gives one.
    let faceWidthMM: ClosedRange<Double>?
    let background: Background
    /// The colour a replaced background is filled with, as 0xRRGGBB.
    let backgroundFill: UInt32
    let glasses: Glasses
    /// A fixed pixel size for digital uploads; otherwise the photo is rendered at `printDPI`.
    let digitalPixels: CGSize?
    let minPixels: CGSize?
    let maxFileKB: Int?
    let notes: [String]
    let infant: Infant?
    let source: URL
    let verified: String
    let confidence: Confidence
    let applicantPhoto: ApplicantPhoto

    static let printDPI: Double = 600

    var title: String { String(localized: "\(country) \(document)", comment: "Country and document, e.g. United States Passport") }
    var aspect: Double { widthMM / heightMM }

    /// The country's flag, from its ISO code; a globe for the EU-wide and generic specs.
    var flag: String {
        switch countryCode {
        case "EU": return "🇪🇺"
        case "XX": return "🌐"
        default:
            return String(String.UnicodeScalarView(countryCode.uppercased().unicodeScalars.compactMap {
                Unicode.Scalar(127_397 + $0.value)
            }))
        }
    }

    var outputPixels: CGSize {
        if let digitalPixels { return digitalPixels }
        return CGSize(
            width: (widthMM / 25.4 * Self.printDPI).rounded(),
            height: (heightMM / 25.4 * Self.printDPI).rounded()
        )
    }

    /// Upload-only specs have an exact pixel size and no printed size, so they get no print sheet.
    var isPrintable: Bool { digitalPixels == nil }

    /// When the values were last confirmed on the official page.
    var verifiedDate: Date? {
        // A calendar day, not an instant: read it in the local time zone so it never shows as the day before.
        let parts = verified.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// "Sep 25, 2026", or the raw value if it isn't a date.
    var verifiedLabel: String {
        verifiedDate?.formatted(date: .abbreviated, time: .omitted) ?? verified
    }

    /// Not confirmed for over six months: two quarterly reviews missed.
    var isStale: Bool {
        guard let verifiedDate else { return true }
        return verifiedDate < Date.now.addingTimeInterval(-183 * 86_400)
    }

    /// Identifies the rules a photo was made with, so saved photos can tell when they've changed.
    var fingerprint: String {
        [
            "\(widthMM)x\(heightMM)", "\(headHeightMM)", headTop.rawValue, "\(String(describing: eyeLineFromBottomMM))",
            "\(String(describing: topMarginMM))", "\(String(describing: faceWidthMM))", background.rawValue, glasses.rawValue,
            "\(String(describing: digitalPixels))", "\(String(describing: maxFileKB))", applicantPhoto.rawValue,
        ].joined(separator: "|")
    }

    var outputDPI: Double { outputPixels.width / (widthMM / 25.4) }

    /// This spec with the baby rules applied, where the issuer states any.
    func forInfant() -> PhotoSpec {
        var copy = self
        if let head = infant?.headHeightMM { copy.headHeightMM = head }
        return copy
    }

    /// Where the head sits when the spec only limits its size: this share of the space left over goes above
    /// the head, the rest below the chin.
    static let spaceAboveHeadShare = 0.4

    static func == (lhs: PhotoSpec, rhs: PhotoSpec) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: Decoding

    private enum CodingKeys: String, CodingKey {
        case id, countryCode, country, document, kind, widthMM, heightMM, sizeLabel, headHeightMM, headTop, eyeLineFromBottomMM,
             topMarginMM, faceWidthMM, background, backgroundFill, glasses, digitalPixels, minPixels, maxFileKB, notes,
             infant, source, verified, confidence, applicantPhoto, schema
    }

    /// A country's name in the app's language. The data files name countries in English, which is kept for
    /// English; other languages use the system's name for the region code.
    static func localizedCountry(code: String, english: String) -> String {
        switch code {
        case "XX": return String(localized: "Other countries")
        case "EU": return String(localized: "Schengen Area")
        default:
            guard let language = Bundle.main.preferredLocalizations.first, !language.hasPrefix("en") else { return english }
            return Locale(identifier: language).localizedString(forRegionCode: code) ?? english
        }
    }

    /// A document's name in the app's language; names not listed here stay as the data file has them.
    static func localizedDocument(_ english: String) -> String {
        switch english {
        case "Passport": String(localized: "Passport")
        case "Passport Card": String(localized: "Passport Card")
        case "Passport & ID Card": String(localized: "Passport & ID Card")
        case "Passport & Passport Card": String(localized: "Passport & Passport Card")
        case "Passport (applying abroad)": String(localized: "Passport (applying abroad)")
        case "Passport (New York Consulate)": String(localized: "Passport (New York Consulate)")
        case "Internal Passport": String(localized: "Internal Passport")
        case "Visa": String(localized: "Visa")
        case "e-Visa", "E-Visa": String(localized: "e-Visa")
        case "ID Card": String(localized: "ID Card")
        case "OCI Card": String(localized: "OCI Card")
        case "Permanent Resident Card": String(localized: "Permanent Resident Card")
        case "USCIS (Green Card, Naturalization, EAD)": String(localized: "USCIS (Green Card, Naturalization, EAD)")
        case "ICAO Standard": String(localized: "ICAO Standard")
        default: english
        }
    }

    /// The newest entry format this app understands. Downloaded entries that need more are skipped.
    static let supportedSchema = 1

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        countryCode = try c.decode(String.self, forKey: .countryCode)
        country = Self.localizedCountry(code: countryCode, english: try c.decode(String.self, forKey: .country))
        document = Self.localizedDocument(try c.decode(String.self, forKey: .document))
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .other
        widthMM = try c.decode(Double.self, forKey: .widthMM)
        heightMM = try c.decode(Double.self, forKey: .heightMM)
        sizeLabel = try c.decode(String.self, forKey: .sizeLabel)
        guard let head = try c.decodeRange(.headHeightMM) else {
            throw DecodingError.dataCorruptedError(forKey: .headHeightMM, in: c, debugDescription: "headHeightMM is required")
        }
        headHeightMM = head
        headTop = try c.decodeIfPresent(HeadTop.self, forKey: .headTop) ?? .hair
        eyeLineFromBottomMM = try c.decodeRange(.eyeLineFromBottomMM)
        topMarginMM = try c.decodeRange(.topMarginMM)
        faceWidthMM = try c.decodeRange(.faceWidthMM)
        background = try c.decode(Background.self, forKey: .background)
        let fill = try c.decodeIfPresent(String.self, forKey: .backgroundFill) ?? "#FFFFFF"
        backgroundFill = UInt32(fill.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        glasses = try c.decodeIfPresent(Glasses.self, forKey: .glasses) ?? .discouraged
        digitalPixels = try c.decodeSize(.digitalPixels)
        minPixels = try c.decodeSize(.minPixels)
        maxFileKB = try c.decodeIfPresent(Int.self, forKey: .maxFileKB)
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        infant = try c.decodeIfPresent(Infant.self, forKey: .infant)
        source = try c.decode(URL.self, forKey: .source)
        verified = try c.decodeIfPresent(String.self, forKey: .verified) ?? ""
        confidence = try c.decodeIfPresent(Confidence.self, forKey: .confidence) ?? .partial
        applicantPhoto = try c.decodeIfPresent(ApplicantPhoto.self, forKey: .applicantPhoto) ?? .accepted
        if let schema = try c.decodeIfPresent(Int.self, forKey: .schema), schema > Self.supportedSchema {
            throw DecodingError.dataCorruptedError(forKey: .schema, in: c, debugDescription: "Needs schema \(schema)")
        }
    }
}

private extension KeyedDecodingContainer {
    /// A `[min, max]` pair, or null.
    nonisolated func decodeRange(_ key: Key) throws -> ClosedRange<Double>? {
        guard let pair = try decodeIfPresent([Double].self, forKey: key), pair.count == 2 else { return nil }
        return Swift.min(pair[0], pair[1])...Swift.max(pair[0], pair[1])
    }

    nonisolated func decodeSize(_ key: Key) throws -> CGSize? {
        guard let pair = try decodeIfPresent([Double].self, forKey: key), pair.count == 2 else { return nil }
        return CGSize(width: pair[0], height: pair[1])
    }
}

extension ClosedRange where Bound == Double {
    nonisolated var mid: Double { (lowerBound + upperBound) / 2 }

    nonisolated func formattedMM() -> String {
        "\(lowerBound.formatted(.number.precision(.fractionLength(0...1))))–\(upperBound.formatted(.number.precision(.fractionLength(0...1)))) mm"
    }
}
