import CoreGraphics
import Foundation
import SwiftData
import UIKit

/// One photo being fitted to a spec: measures the head and background, proposes the crop, replaces the
/// background when it doesn't meet the rules, keeps the checks current while the person pans and zooms, and
/// saves the result.
@Observable
final class EditorModel {
    enum Phase: Equatable {
        case measuring
        case ready
        case failed(String)
    }

    enum Review: Equatable {
        case idle
        case running
        case done(PhotoObservations, ReviewEngine)
        case unavailable(String)
    }

    let image: CGImage
    let imageSize: CGSize
    /// The saved photo being adjusted again, if any.
    let editing: SavedPhoto?

    private(set) var spec: PhotoSpec
    private(set) var phase: Phase = .measuring
    private(set) var measurement: FaceMeasurement?
    private(set) var review: Review = .idle
    private(set) var backgroundStats: BackgroundStats?
    /// The photo as shown and saved: the original, or the original with its background replaced.
    private(set) var displayImage: UIImage
    /// The crop in the original's pixels, top-left origin. Updated live while panning and zooming.
    var crop: CGRect = .zero
    /// What auto-crop proposes for the current spec; the target oval is drawn from it.
    private(set) var autoCropRect: CGRect = .zero

    /// Replace a background that doesn't meet the rules. On by default; remembered across photos.
    var replaceBackground: Bool {
        didSet {
            UserDefaults.standard.set(replaceBackground, forKey: Self.replaceBackgroundKey)
            Task { await updateComposite() }
        }
    }

    /// Apply the spec's rules for babies. Only offered when the spec has them.
    var isInfant = false {
        didSet { proposeCrop() }
    }

    private var personMask: CGImage?
    private var composite: (fill: UInt32, image: CGImage)?
    private let reviewer = PhotoReviewer()
    private let initialCrop: CGRect?
    #if DEBUG
    /// Skips Vision with known measurements (the demo photo).
    var presetMeasurement: FaceMeasurement?
    #endif
    private static let replaceBackgroundKey = "replaceBackground"

    init(image: CGImage, spec: PhotoSpec, infant: Bool = false, editing: SavedPhoto? = nil) {
        self.image = image
        self.displayImage = UIImage(cgImage: image)
        self.imageSize = CGSize(width: image.width, height: image.height)
        self.spec = spec
        self.editing = editing
        self.initialCrop = editing?.crop
        self.isInfant = editing?.isInfant ?? (infant && spec.infant != nil)
        self.replaceBackground = editing?.backgroundReplaced ?? UserDefaults.standard.object(forKey: Self.replaceBackgroundKey) as? Bool ?? false
    }

    /// The spec as applied to this photo: with the baby rules when they're on.
    var effectiveSpec: PhotoSpec { isInfant && spec.infant != nil ? spec.forInfant() : spec }

    /// The measurement with the head top this spec measures to.
    var fittedMeasurement: FaceMeasurement? { measurement?.measuredTo(spec.headTop) }

    func start() async {
        guard phase == .measuring else { return }
        #if DEBUG
        if let presetMeasurement {
            measurement = presetMeasurement
            backgroundStats = BackgroundStats(red: 0.80, green: 0.87, blue: 0.93, unevenness: 0.01)
            proposeCrop()
            phase = .ready
            await runReview()
            return
        }
        #endif
        personMask = await Background.personMask(for: image)
        do {
            measurement = try await FaceMeasurer.measure(image, personMask: personMask)
        } catch {
            // Vision found no face: ask the model where the head is, so the photo can still be cropped.
            do {
                measurement = try await reviewer.locateHead(image)
            } catch {
                phase = .failed(String(localized: "No face was found. Choose a photo that shows your face clearly, looking at the camera."))
                return
            }
        }
        if let personMask { backgroundStats = await Background.measure(image, mask: personMask) }
        proposeCrop()
        if let initialCrop, initialCrop.width > 0 { crop = initialCrop }
        phase = .ready
        await updateComposite()
        await runReview()
    }

    func select(_ newSpec: PhotoSpec) {
        guard newSpec != spec else { return }
        spec = newSpec
        if spec.infant == nil { isInfant = false }
        proposeCrop()
        Task { await updateComposite() }
    }

    /// Back to the auto crop for the current spec.
    func resetToAuto() {
        crop = autoCropRect
    }

    private func proposeCrop() {
        guard let fittedMeasurement else { return }
        autoCropRect = CropSolver.autoCrop(measurement: fittedMeasurement, spec: effectiveSpec, imageSize: imageSize)
        crop = autoCropRect
    }

    // MARK: Background

    /// How the original background compares with the spec, from the pixels and from the model.
    var originalBackgroundStatus: CheckStatus? {
        let measured = backgroundStats.map { $0.isPlain ? Checks.backgroundStatus($0.tone, rule: spec.background) : .fail }
        var model: CheckStatus?
        if case .done(let observations, _) = review {
            let tone = BackgroundTone(rawValue: observations.backgroundTone) ?? .busy
            model = observations.backgroundIsPlain && !observations.shadowOnBackground
                ? Checks.backgroundStatus(tone, rule: spec.background) : .fail
        }
        return [measured, model].compactMap { $0 }.max()
    }

    /// The background is replaced when it doesn't pass, replacing is on, and the person could be separated.
    var backgroundIsReplaced: Bool {
        replaceBackground && personMask != nil && (originalBackgroundStatus.map { $0 != .pass } ?? false)
    }

    var canReplaceBackground: Bool { personMask != nil }

    private func updateComposite() async {
        guard backgroundIsReplaced, let personMask else {
            displayImage = UIImage(cgImage: image)
            return
        }
        let fill = spec.backgroundFill
        if composite?.fill != fill, let replaced = await Background.replace(image, mask: personMask, fill: fill) {
            composite = (fill, replaced)
        }
        displayImage = UIImage(cgImage: composite?.image ?? image)
    }

    // MARK: Review

    func runReview() async {
        review = .running
        // The model sees the original (not the replaced background) around the area auto-crop chose, at a
        // size that keeps detail without spending the context on pixels.
        let region = autoCropRect.intersection(CGRect(origin: .zero, size: imageSize))
        let source = region.isNull || region.isEmpty ? CGRect(origin: .zero, size: imageSize) : region
        let scale = min(1, 1024 / max(source.width, source.height))
        guard let preview = PhotoRenderer.render(image, crop: source, size: CGSize(width: (source.width * scale).rounded(), height: (source.height * scale).rounded())) else {
            review = .unavailable(String(localized: "The photo couldn’t be prepared for review."))
            return
        }
        do {
            let (observations, engine) = try await reviewer.review(preview)
            review = .done(observations, engine)
        } catch {
            review = .unavailable(error.localizedDescription)
        }
        // The review may have found a background problem the pixels didn't.
        await updateComposite()
    }

    // MARK: Checks

    var geometry: CropGeometry? {
        guard let fittedMeasurement, crop.width > 0 else { return nil }
        return CropSolver.geometry(of: crop, measurement: fittedMeasurement, spec: effectiveSpec, imageSize: imageSize)
    }

    var measuredChecks: [CheckResult] {
        guard let fittedMeasurement, let geometry else { return [] }
        return Checks.geometry(geometry, measurement: fittedMeasurement, spec: effectiveSpec)
    }

    var backgroundCheck: CheckResult? {
        guard measurement != nil else { return nil }
        var observations: PhotoObservations?
        if case .done(let o, _) = review { observations = o }
        return Checks.background(spec: spec, stats: backgroundStats, observations: observations, replaced: backgroundIsReplaced)
    }

    var modelChecks: [CheckResult] {
        switch review {
        case .done(let observations, _):
            Checks.observations(observations, spec: effectiveSpec, infant: isInfant, backgroundReplaced: backgroundIsReplaced)
        case .unavailable: Checks.manual(spec: spec)
        case .idle, .running: []
        }
    }

    /// Whether the issuer accepts a photo made at home at all.
    var acceptanceCheck: CheckResult? {
        SpecNoticesSection.applicantMessage(spec).map {
            CheckResult(id: "accepted", title: String(localized: "Accepted from you"), detail: $0, status: .fail, source: .measured)
        }
    }

    var checks: [CheckResult] { [acceptanceCheck].compactMap { $0 } + measuredChecks + [backgroundCheck].compactMap { $0 } + modelChecks }

    func status(of id: String) -> CheckStatus {
        measuredChecks.first { $0.id == id }?.status ?? .pending
    }

    /// Checks that need a look or fail. Checks left to the person don't count.
    var openIssues: Int {
        checks.filter { $0.status == .attention || $0.status == .fail }.count
    }

    // MARK: Output

    private var outputSource: CGImage { backgroundIsReplaced ? composite?.image ?? image : image }

    func render() -> CGImage? {
        PhotoRenderer.render(outputSource, crop: crop, size: spec.outputPixels)
    }

    /// The finished JPEG, compressed to fit the spec's upload limit when it has one.
    func renderJPEG() -> Data? {
        guard let rendered = render() else { return nil }
        return PhotoRenderer.jpegData(rendered, dpi: spec.outputDPI, maxKB: spec.maxFileKB)
    }

    enum SaveError: LocalizedError {
        case render

        var errorDescription: String? { String(localized: "The photo couldn’t be rendered.") }
    }

    /// Saves the finished photo (and a print sheet, if asked) to the photo library, the app, or both.
    func save(name: String, toPhotos: Bool, inApp: Bool, paper: PrintSheet.Paper?, context: ModelContext) async throws {
        let date = editing?.createdAt ?? Date()
        guard let rendered = render(), let jpeg = PhotoRenderer.jpegData(rendered, dpi: spec.outputDPI, maxKB: spec.maxFileKB) else { throw SaveError.render }
        let exportName = PhotoStore.exportFileName(name: name, date: date)

        var sheetJPEG: Data?
        if let paper {
            guard let sheet = PrintSheet.render(rendered, spec: spec, paper: paper),
                  let data = PhotoRenderer.jpegData(sheet, dpi: PrintSheet.dpi) else { throw SaveError.render }
            sheetJPEG = data
        }

        if toPhotos {
            try await PhotoLibrarySaver.save(jpeg, fileName: exportName)
            if let sheetJPEG, let paper {
                try await PhotoLibrarySaver.save(sheetJPEG, fileName: PhotoStore.exportFileName(name: name, date: date, suffix: "print \(paper.fileLabel)"))
            }
        }
        guard inApp else { return }

        let id = UUID().uuidString
        let fileName = "\(id).jpg"
        try PhotoStore.write(jpeg, named: fileName)

        if let editing {
            PhotoStore.remove([editing.fileName])
            editing.name = name
            editing.specID = spec.id
            editing.fileName = fileName
            editing.cropX = crop.minX
            editing.cropY = crop.minY
            editing.cropWidth = crop.width
            editing.cropHeight = crop.height
            editing.pixelWidth = Int(spec.outputPixels.width)
            editing.pixelHeight = Int(spec.outputPixels.height)
            editing.openIssues = openIssues
            editing.backgroundReplaced = backgroundIsReplaced
            editing.isInfant = isInfant
            editing.specFingerprint = spec.fingerprint
        } else {
            // Keep the original too, so the crop can be adjusted later without losing pixels.
            let originalName = "\(id)-original.jpg"
            guard let original = PhotoRenderer.jpegData(image, dpi: 72, quality: 0.95) else { throw SaveError.render }
            try PhotoStore.write(original, named: originalName)
            let photo = SavedPhoto(
                name: name, spec: spec, createdAt: date, fileName: fileName, originalFileName: originalName,
                crop: crop, pixels: spec.outputPixels, openIssues: openIssues
            )
            photo.backgroundReplaced = backgroundIsReplaced
            photo.isInfant = isInfant
            photo.specFingerprint = spec.fingerprint
            context.insert(photo)
        }
        try context.save()
    }
}
