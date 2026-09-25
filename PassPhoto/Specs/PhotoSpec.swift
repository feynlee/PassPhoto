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
            case .passport: "Passports"
            case .visa: "Visas"
            case .id: "ID Cards"
            case .residence: "Residence"
            case .license: "Licenses"
            case .other: "Other"
            }
        }
    }

    enum Background: String, Sendable, Decodable {
        case white, whiteOrOffWhite, creamOrLightGrey, lightGrey, plainLight, lightNotWhite, lightBlue, blue, red

        var requirement: String {
            switch self {
            case .white: "Plain white"
            case .whiteOrOffWhite: "Plain white or off-white"
            case .creamOrLightGrey: "Plain cream or light grey"
            case .lightGrey: "Plain light grey"
            case .plainLight: "Plain and light-coloured"
            case .lightNotWhite: "Plain light colour, not white"
            case .lightBlue: "Plain light blue"
            case .blue: "Plain blue"
            case .red: "Plain red"
            }
        }
    }

    enum Glasses: String, Sendable, Decodable {
        case notAllowed, discouraged, allowed

        var requirement: String {
            switch self {
            case .notAllowed: "Glasses aren’t allowed"
            case .discouraged: "Remove glasses if you can"
            case .allowed: "Glasses allowed without glare or tint"
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

    static let printDPI: Double = 600

    var title: String { "\(country) \(document)" }
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
             infant, source, verified, confidence
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        countryCode = try c.decode(String.self, forKey: .countryCode)
        country = try c.decode(String.self, forKey: .country)
        document = try c.decode(String.self, forKey: .document)
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
