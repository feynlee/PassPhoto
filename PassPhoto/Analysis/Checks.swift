import Foundation

nonisolated enum CheckStatus: Int, Sendable, Comparable {
    case pass, pending, attention, fail

    static func < (lhs: CheckStatus, rhs: CheckStatus) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated struct CheckResult: Identifiable, Sendable, Equatable {
    enum Source: Sendable { case measured, model, yourself }

    let id: String
    let title: String
    let detail: String
    let status: CheckStatus
    let source: Source
}

/// Turns measurements and the model's observations into pass / attention / fail results for one spec.
nonisolated enum Checks {
    /// How far outside a range still counts as "needs a look" rather than a fail.
    static let nearMissMM = 1.0

    static func geometry(_ g: CropGeometry, measurement m: FaceMeasurement, spec: PhotoSpec) -> [CheckResult] {
        var results: [CheckResult] = []

        let crownNote = m.crownIsEstimated ? " The top of the head was estimated; line it up with the guide." : ""
        results.append(range(
            id: "head", title: "Head size", value: g.headMM, allowed: spec.headHeightMM,
            what: "chin to top of head", extra: crownNote
        ))
        if let eye = spec.eyeLineFromBottomMM {
            results.append(range(id: "eyes", title: "Eye height", value: g.eyeFromBottomMM, allowed: eye, what: "from the bottom edge"))
        }
        if let margin = spec.topMarginMM {
            results.append(range(id: "top", title: "Space above head", value: g.topMarginMM, allowed: margin, what: "above the head"))
        } else if g.topMarginMM < 1 {
            results.append(CheckResult(
                id: "top", title: "Space above head",
                detail: "The top of the head touches the edge. Zoom out a little.",
                status: .fail, source: .measured
            ))
        }
        if let width = spec.faceWidthMM {
            results.append(range(id: "width", title: "Face width", value: g.faceWidthMM, allowed: width, what: "cheek to cheek"))
        }

        let offset = abs(g.centerOffsetMM)
        results.append(CheckResult(
            id: "center", title: "Centred",
            detail: offset <= CropSolver.centerToleranceMM
                ? "The face is centred."
                : "The face is \(mm(offset)) \(g.centerOffsetMM > 0 ? "right" : "left") of centre.",
            status: offset <= CropSolver.centerToleranceMM ? .pass : offset <= 2.5 ? .attention : .fail,
            source: .measured
        ))

        if g.outsideFraction > 0.001 {
            results.append(CheckResult(
                id: "edges", title: "Photo fills the frame",
                detail: "\(Int((g.outsideFraction * 100).rounded(.up)))% of the frame is past the photo’s edge and will be white. Retake with more space around you, or zoom in.",
                status: g.outsideFraction < 0.03 ? .attention : .fail, source: .measured
            ))
        }

        // The source should have at least 300 pixels per inch of the finished photo, or the output size if smaller.
        let needed = min(spec.outputPixels.width, spec.widthMM / 25.4 * 300)
        let ratio = g.sourcePixelsWide / needed
        results.append(CheckResult(
            id: "resolution", title: "Resolution",
            detail: ratio >= 1
                ? "\(Int(g.sourcePixelsWide)) pixels across; sharp enough to print."
                : "Only \(Int(g.sourcePixelsWide)) pixels across; \(Int(needed)) are needed. Move closer or use the back camera.",
            status: ratio >= 1 ? .pass : ratio >= 0.66 ? .attention : .fail,
            source: .measured
        ))

        let roll = abs(m.rollDegrees)
        results.append(CheckResult(
            id: "level", title: "Head level",
            detail: roll <= 3
                ? "The eyes are level."
                : "The head tilts \(Int(roll.rounded()))°. Retake with your head straight.",
            status: roll <= 3 ? .pass : roll <= 6 ? .attention : .fail,
            source: .measured
        ))

        if m.faceCount > 1 {
            results.append(CheckResult(
                id: "people", title: "Only you",
                detail: "\(m.faceCount) faces were found. Only the applicant can be in the photo.",
                status: .fail, source: .measured
            ))
        }
        return results
    }

    /// The background, from the measured pixels and the model's description. A replaced background passes.
    static func background(spec: PhotoSpec, stats: BackgroundStats?, observations o: PhotoObservations?, replaced: Bool) -> CheckResult {
        let need = spec.background.requirement.lowercased()
        let modelTone = o.flatMap { BackgroundTone(rawValue: $0.backgroundTone) }
        let tone = stats?.tone ?? modelTone
        let described = tone.map { "Your background is \($0.label)" } ?? "Your background"
        if replaced {
            return CheckResult(id: "background", title: "Background",
                               detail: "\(described); replaced with \(need) as required. Turn off Replace Background to keep the original.",
                               status: .pass, source: .measured)
        }
        let plain = (stats?.isPlain ?? true) && (o?.backgroundIsPlain ?? true)
        let statuses = [stats.map { backgroundStatus($0.tone, rule: spec.background) },
                        modelTone.map { backgroundStatus($0, rule: spec.background) }].compactMap { $0 }
        guard !statuses.isEmpty else {
            return CheckResult(id: "background", title: "Background", detail: "Needs: \(need).", status: .pending, source: .yourself)
        }
        let status = plain ? statuses.max()! : .fail
        let detail = plain
            ? "\(described). Needs: \(need)."
            : "\(described) and isn’t plain: there’s a pattern, texture or something behind you. Needs: \(need)."
        return CheckResult(id: "background", title: "Background", detail: detail, status: status, source: o == nil ? .measured : .model)
    }

    static func observations(_ o: PhotoObservations, spec: PhotoSpec, infant: Bool = false, backgroundReplaced: Bool = false) -> [CheckResult] {
        var results: [CheckResult] = []
        let babyEyes = infant && spec.infant?.eyesMayBeClosed == true
        let babyMouth = infant && spec.infant?.mouthMayBeOpen == true

        results.append(flag(id: "lighting", title: "Lighting", ok: o.lightingIsEven && !o.shadowOnFace,
                            pass: "Even, with no shadows on the face.",
                            problem: o.shadowOnFace ? "There are shadows on the face. Face a window or add light from the front." : "The face is too dark or too bright."))
        results.append(flag(id: "shadow", title: "No background shadow", ok: !o.shadowOnBackground || backgroundReplaced,
                            pass: "No shadow behind you.",
                            problem: "Your shadow shows on the background. Step away from the wall.", failing: .attention))

        let neutral = (o.expression == "neutral" || babyMouth) && (o.mouthClosed || babyMouth)
        results.append(CheckResult(
            id: "expression", title: "Neutral expression",
            detail: neutral ? "Neutral, mouth closed."
                : !o.mouthClosed ? "The mouth is open. Close it and relax your face."
                : "The expression isn’t neutral. Don’t smile.",
            status: neutral ? .pass : o.expression == "slightSmile" && o.mouthClosed ? .attention : .fail,
            source: .model
        ))
        results.append(flag(id: "eyesOpen", title: "Eyes open", ok: (o.eyesOpen || babyEyes) && !o.faceObscured && !o.redEye,
                            pass: babyEyes && !o.eyesOpen ? "Closed eyes are allowed for babies." : "Both eyes open and visible.",
                            problem: o.redEye ? "The eyes show red-eye. Retake without flash."
                                : o.faceObscured ? "Hair or something else covers part of the face." : "Both eyes need to be open and visible."))
        results.append(flag(id: "facing", title: "Facing the camera", ok: o.facingCamera,
                            pass: "Looking straight at the camera.", problem: "Turn to face the camera directly."))

        let glasses = o.glasses
        let glassesStatus: CheckStatus
        let glassesDetail: String
        switch (glasses, spec.glasses) {
        case ("none", _):
            glassesStatus = .pass; glassesDetail = "No glasses."
        case (_, .notAllowed):
            glassesStatus = .fail; glassesDetail = "\(spec.country) doesn’t allow glasses. Take them off."
        case ("tinted", _):
            glassesStatus = .fail; glassesDetail = "Tinted glasses aren’t allowed."
        case (_, _) where o.glassesGlare:
            glassesStatus = .fail; glassesDetail = "There’s glare on the glasses. Tilt them down slightly or take them off."
        case (_, .discouraged):
            glassesStatus = .attention; glassesDetail = "Glasses are discouraged. Take them off if you can."
        default:
            glassesStatus = .pass; glassesDetail = "Clear glasses with no glare."
        }
        results.append(CheckResult(id: "glasses", title: "Glasses", detail: glassesDetail, status: glassesStatus, source: .model))

        results.append(flag(id: "headCovering", title: "No head covering", ok: !o.headCovering,
                            pass: "Nothing on the head.",
                            problem: "Remove hats and headbands. Religious or medical coverings are allowed with a statement.", failing: .attention))
        results.append(flag(id: "focus", title: "Sharp", ok: o.inFocus, pass: "In focus.", problem: "The photo is blurry. Hold still or use a tripod."))
        results.append(flag(id: "alone", title: "Nothing else in frame", ok: !o.otherPeopleOrObjects,
                            pass: "Only you in the photo.", problem: "Someone else, a hand or an object shows in the photo."))
        results.append(flag(id: "unedited", title: "Unedited", ok: !o.looksEdited,
                            pass: "Looks unedited.", problem: "The photo looks filtered or retouched. Use the original.", failing: .attention))
        return results
    }

    /// When no model can look at the photo, the person checks these themselves.
    static func manual(spec: PhotoSpec) -> [CheckResult] {
        [
            ("background", "Background", spec.background.requirement + ", with no shadows."),
            ("expression", "Neutral expression", "Mouth closed, both eyes open, no smile."),
            ("glasses", "Glasses", spec.glasses.requirement + "."),
            ("lighting", "Lighting", "Even light on the face, no shadows or flash glare."),
        ].map { CheckResult(id: $0.0, title: $0.1, detail: $0.2, status: .pending, source: .yourself) }
    }

    static func backgroundStatus(_ tone: BackgroundTone, rule: PhotoSpec.Background) -> CheckStatus {
        switch rule {
        case .white:
            switch tone { case .white: .pass; case .offWhite: .attention; default: .fail }
        case .whiteOrOffWhite:
            switch tone { case .white, .offWhite: .pass; case .cream, .lightGrey: .attention; default: .fail }
        case .creamOrLightGrey:
            switch tone { case .cream, .lightGrey, .offWhite: .pass; case .white: .attention; default: .fail }
        case .lightGrey:
            switch tone { case .lightGrey: .pass; case .white, .offWhite, .lightBlue, .cream, .otherLight: .attention; default: .fail }
        case .plainLight:
            switch tone { case .dark, .busy, .blue, .red: .fail; default: .pass }
        case .lightNotWhite:
            switch tone { case .lightGrey, .lightBlue: .pass; case .offWhite, .cream, .otherLight: .attention; default: .fail }
        case .lightBlue:
            switch tone { case .lightBlue: .pass; case .blue: .attention; default: .fail }
        case .blue:
            switch tone { case .blue: .pass; case .lightBlue: .attention; default: .fail }
        case .red:
            switch tone { case .red: .pass; default: .fail }
        }
    }

    // MARK: Helpers

    private static func range(id: String, title: String, value: Double, allowed: ClosedRange<Double>, what: String, extra: String = "") -> CheckResult {
        let status: CheckStatus = allowed.contains(value) ? .pass
            : (value >= allowed.lowerBound - nearMissMM && value <= allowed.upperBound + nearMissMM) ? .attention : .fail
        let hint = value < allowed.lowerBound
            ? (id == "head" || id == "width" ? " Zoom in." : id == "eyes" ? " Move the photo up." : " Move the photo down.")
            : value > allowed.upperBound
            ? (id == "head" || id == "width" ? " Zoom out." : id == "eyes" ? " Move the photo down." : " Move the photo up.")
            : ""
        return CheckResult(
            id: id, title: title,
            detail: "\(mm(value)) \(what); needs \(allowed.formattedMM()).\(status == .pass ? "" : hint)\(extra)",
            status: status, source: .measured
        )
    }

    private static func flag(id: String, title: String, ok: Bool, pass: String, problem: String, failing: CheckStatus = .fail) -> CheckResult {
        CheckResult(id: id, title: title, detail: ok ? pass : problem, status: ok ? .pass : failing, source: .model)
    }

    static func mm(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) mm"
    }
}
