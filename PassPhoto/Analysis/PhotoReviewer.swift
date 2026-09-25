import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import os

/// What the model sees in a photo. The fields describe the photo, not a verdict: the app compares them with
/// each country's rules itself, so switching countries never needs a second request.
@Generable(description: "What a portrait photo shows, for checking it against passport and visa photo rules")
nonisolated struct PhotoObservations: Equatable {
    @Guide(description: "The background's colour behind the person.", .anyOf(BackgroundTone.allCases.map(\.rawValue)))
    var backgroundTone: String

    @Guide(description: "True if the background is one plain colour with no pattern, texture, objects, doors, furniture or scenery.")
    var backgroundIsPlain: Bool

    @Guide(description: "True if the person casts a visible shadow on the background.")
    var shadowOnBackground: Bool

    @Guide(description: "True if there are visible shadows across the face, such as one side much darker than the other or shadows under a hat brim.")
    var shadowOnFace: Bool

    @Guide(description: "True if the face is evenly lit, neither overexposed nor too dark, with natural skin tones.")
    var lightingIsEven: Bool

    @Guide(description: "The facial expression.", .anyOf(["neutral", "slightSmile", "smiling", "other"]))
    var expression: String

    @Guide(description: "True if the mouth is closed.")
    var mouthClosed: Bool

    @Guide(description: "True if both eyes are open and clearly visible.")
    var eyesOpen: Bool

    @Guide(description: "True if the person faces the camera directly, not turned or tilted.")
    var facingCamera: Bool

    @Guide(description: "Glasses worn in the photo.", .anyOf(["none", "clear", "tinted"]))
    var glasses: String

    @Guide(description: "True if there is glare or reflection on glasses. False if there are no glasses.")
    var glassesGlare: Bool

    @Guide(description: "True if the person wears a hat, cap, headband or other head covering.")
    var headCovering: Bool

    @Guide(description: "True if hair or anything else covers the eyes, eyebrows or part of the face.")
    var faceObscured: Bool

    @Guide(description: "True if the face is sharp and in focus, without blur, noise or pixelation.")
    var inFocus: Bool

    @Guide(description: "True if the eyes show red-eye from a flash.")
    var redEye: Bool

    @Guide(description: "True if anyone else, a hand or an object other than clothing appears in the photo.")
    var otherPeopleOrObjects: Bool

    @Guide(description: "True if the photo looks retouched, filtered or edited, such as smoothed skin or changed colours.")
    var looksEdited: Bool
}

nonisolated enum BackgroundTone: String, CaseIterable, Sendable {
    case white, offWhite, cream, lightGrey, lightBlue, blue, red, otherLight, dark, busy

    var label: String {
        switch self {
        case .white: "white"
        case .offWhite: "off-white"
        case .cream: "cream"
        case .lightGrey: "light grey"
        case .lightBlue: "light blue"
        case .blue: "blue"
        case .red: "red"
        case .otherLight: "a light colour"
        case .dark: "dark"
        case .busy: "busy"
        }
    }
}

/// Where the head is, as the model sees it: used only when Vision can't find a face.
@Generable(description: "Where one person's head is in a photo, as fractions of the photo's width and height from its top-left corner")
nonisolated struct HeadLocation {
    @Guide(description: "True if exactly one person's face is clearly visible.")
    var faceFound: Bool
    @Guide(description: "The top of the head including hair, as a fraction of the height from the top.", .range(0...1))
    var crown: Double
    @Guide(description: "The bottom of the chin, as a fraction of the height from the top.", .range(0...1))
    var chin: Double
    @Guide(description: "The line through the pupils, as a fraction of the height from the top.", .range(0...1))
    var eyes: Double
    @Guide(description: "The centre of the face, as a fraction of the width from the left.", .range(0...1))
    var center: Double
    @Guide(description: "The face's width from cheek to cheek, as a fraction of the photo's width.", .range(0...1))
    var faceWidth: Double
}

nonisolated enum ReviewEngine: String, Sendable {
    case privateCloudCompute
    case onDevice

    var label: String {
        switch self {
        case .privateCloudCompute: "Private Cloud Compute"
        case .onDevice: "on-device model"
        }
    }
}

nonisolated enum ReviewError: LocalizedError, Equatable {
    case unavailable(String)
    case quotaReached(resetDate: Date?)
    case network
    case noVision
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .quotaReached(let date):
            date.map { "Private Cloud Compute’s daily limit is reached. It resets \($0.formatted(.relative(presentation: .named)))." }
                ?? "Private Cloud Compute’s daily limit is reached."
        case .network: "Private Cloud Compute couldn’t be reached."
        case .noVision: "The model available on this iPhone can’t look at photos."
        case .failed(let message): message
        }
    }

    /// Errors that mean "try the on-device model instead" rather than "this photo can't be reviewed".
    var allowsFallback: Bool {
        switch self {
        case .unavailable, .quotaReached, .network, .noVision: true
        case .failed: false
        }
    }
}

/// Reviews a photo with Apple's Private Cloud Compute model, falling back to the on-device model when PCC
/// can't be used. Each photo gets a fresh session.
actor PhotoReviewer {
    private let pcc = PrivateCloudComputeLanguageModel()
    private let onDevice = SystemLanguageModel.default
    private let logger = Logger(subsystem: "liziyue.PassPhoto", category: "Review")

    static let instructions = """
        You check portrait photos for passport, visa and ID card applications. Describe only what is visible \
        in the photo. Be strict: an official will reject a photo for a faint shadow, a slight smile, glare on \
        glasses or a background that isn't one plain colour. When unsure, report the problem.
        """

    func review(_ image: CGImage) async throws -> (PhotoObservations, ReviewEngine) {
        do {
            return (try await withPrivateCloud { model in
                try await self.respond(model: model, image: image, generating: PhotoObservations.self,
                                       prompt: "Describe this photo for a passport photo check.")
            }, .privateCloudCompute)
        } catch let error as ReviewError where error.allowsFallback {
            logger.notice("PCC unavailable, using on-device model: \(error.localizedDescription, privacy: .public)")
        }
        return (try await withOnDevice { model in
            try await self.respond(model: model, image: image, generating: PhotoObservations.self,
                                   prompt: "Describe this photo for a passport photo check.")
        }, .onDevice)
    }

    /// Finds the head when Vision can't, so the photo can still be cropped.
    func locateHead(_ image: CGImage) async throws -> FaceMeasurement {
        let prompt = "Find the person's head in this photo."
        let location: HeadLocation
        do {
            location = try await withPrivateCloud { model in
                try await self.respond(model: model, image: image, generating: HeadLocation.self, prompt: prompt)
            }
        } catch let error as ReviewError where error.allowsFallback {
            location = try await withOnDevice { model in
                try await self.respond(model: model, image: image, generating: HeadLocation.self, prompt: prompt)
            }
        }
        guard location.faceFound, location.chin > location.crown, location.eyes > location.crown, location.chin > location.eyes else {
            throw MeasureError.noFace
        }
        let width = Double(image.width), height = Double(image.height)
        return FaceMeasurement(
            crownY: location.crown * height,
            skullTopY: location.chin * height - (location.chin - location.eyes) * height * FaceMeasurer.skullToChinPerEyeToChin,
            chinY: location.chin * height,
            eyeY: location.eyes * height,
            centerX: location.center * width,
            faceWidth: location.faceWidth * width,
            rollDegrees: 0,
            yawDegrees: nil,
            faceCount: 1,
            crownIsEstimated: true,
            source: .privateCloud
        )
    }

    /// Tells the UI whether PCC can be used right now, and why not.
    nonisolated static func privateCloudStatus() -> String? {
        let model = PrivateCloudComputeLanguageModel()
        switch model.availability {
        case .available:
            return model.quotaUsage.isLimitReached ? ReviewError.quotaReached(resetDate: model.quotaUsage.resetDate).localizedDescription : nil
        case .unavailable(.deviceNotEligible): return "This iPhone doesn’t support Private Cloud Compute."
        case .unavailable(.systemNotReady): return "Apple Intelligence isn’t ready yet."
        case .unavailable: return "Private Cloud Compute is unavailable."
        }
    }

    // MARK: Engines

    private func withPrivateCloud<T>(_ body: (PrivateCloudComputeLanguageModel) async throws -> T) async throws -> T {
        switch pcc.availability {
        case .available: break
        case .unavailable(.deviceNotEligible): throw ReviewError.unavailable("This iPhone doesn’t support Private Cloud Compute.")
        case .unavailable(.systemNotReady): throw ReviewError.unavailable("Apple Intelligence isn’t ready yet.")
        case .unavailable: throw ReviewError.unavailable("Private Cloud Compute is unavailable.")
        }
        if pcc.quotaUsage.isLimitReached { throw ReviewError.quotaReached(resetDate: pcc.quotaUsage.resetDate) }
        guard pcc.capabilities.contains(.vision) else { throw ReviewError.noVision }
        do {
            return try await body(pcc)
        } catch let error as PrivateCloudComputeLanguageModel.Error {
            logger.error("PCC error: \(String(describing: error), privacy: .public)")
            switch error {
            case .networkFailure: throw ReviewError.network
            case .quotaLimitReached(let details): throw ReviewError.quotaReached(resetDate: details.resetDate)
            case .serviceUnavailable: throw ReviewError.unavailable("Private Cloud Compute is unavailable.")
            @unknown default: throw ReviewError.failed(String(describing: error))
            }
        } catch let error as LanguageModelError {
            if case .rateLimited(let details) = error { throw ReviewError.quotaReached(resetDate: details.resetDate) }
            throw ReviewError.failed(String(describing: error))
        }
    }

    private func withOnDevice<T>(_ body: (SystemLanguageModel) async throws -> T) async throws -> T {
        guard onDevice.isAvailable else { throw ReviewError.unavailable("Apple Intelligence isn’t available on this iPhone.") }
        guard onDevice.capabilities.contains(.vision) else { throw ReviewError.noVision }
        do {
            return try await body(onDevice)
        } catch {
            throw ReviewError.failed(String(describing: error))
        }
    }

    private func respond<Model: LanguageModel, T: Generable>(model: Model, image: CGImage, generating type: T.Type, prompt text: String) async throws -> T {
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let prompt = Prompt {
            text
            Attachment(image, orientation: .up).label("photo")
        }
        // Greedy sampling: the same photo should always get the same review.
        let response = try await session.respond(to: prompt, generating: type, options: GenerationOptions(samplingMode: .greedy))
        return response.content
    }
}
