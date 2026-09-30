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

        let crownNote = m.crownIsEstimated ? String(localized: " The top of the head was estimated; line it up with the guide.") : ""
        results.append(range(
            id: "head", title: String(localized: "Head size"), value: g.headMM, allowed: spec.headHeightMM,
            what: String(localized: "chin to top of head"), extra: crownNote
        ))
        if let eye = spec.eyeLineFromBottomMM {
            results.append(range(id: "eyes", title: String(localized: "Eye height"), value: g.eyeFromBottomMM, allowed: eye, what: String(localized: "from the bottom edge")))
        }
        if let margin = spec.topMarginMM {
            results.append(range(id: "top", title: String(localized: "Space above head"), value: g.topMarginMM, allowed: margin, what: String(localized: "above the head")))
        } else if g.topMarginMM < 1 {
            results.append(CheckResult(
                id: "top", title: String(localized: "Space above head"),
                detail: String(localized: "The top of the head touches the edge. Zoom out a little."),
                status: .fail, source: .measured
            ))
        }
        if let width = spec.faceWidthMM {
            results.append(range(id: "width", title: String(localized: "Face width"), value: g.faceWidthMM, allowed: width, what: String(localized: "cheek to cheek")))
        }

        let offset = abs(g.centerOffsetMM)
        results.append(CheckResult(
            id: "center", title: String(localized: "Centred"),
            detail: offset <= CropSolver.centerToleranceMM
                ? String(localized: "The face is centred.")
                : (g.centerOffsetMM > 0 ? String(localized: "The face is \(mm(offset)) right of centre.") : String(localized: "The face is \(mm(offset)) left of centre.")),
            status: offset <= CropSolver.centerToleranceMM ? .pass : offset <= 2.5 ? .attention : .fail,
            source: .measured
        ))

        if g.outsideFraction > 0.001 {
            results.append(CheckResult(
                id: "edges", title: String(localized: "Photo fills the frame"),
                detail: String(localized: "\(Int((g.outsideFraction * 100).rounded(.up)))% of the frame is past the photo’s edge and will be white. Retake with more space around you, or zoom in."),
                status: g.outsideFraction < 0.03 ? .attention : .fail, source: .measured
            ))
        }

        // The source should have at least 300 pixels per inch of the finished photo, or the output size if smaller.
        let needed = min(spec.outputPixels.width, spec.widthMM / 25.4 * 300)
        let ratio = g.sourcePixelsWide / needed
        results.append(CheckResult(
            id: "resolution", title: String(localized: "Resolution"),
            detail: ratio >= 1
                ? String(localized: "\(Int(g.sourcePixelsWide)) pixels across; sharp enough to print.")
                : String(localized: "Only \(Int(g.sourcePixelsWide)) pixels across; \(Int(needed)) are needed. Move closer or use the back camera."),
            status: ratio >= 1 ? .pass : ratio >= 0.66 ? .attention : .fail,
            source: .measured
        ))

        let roll = abs(m.rollDegrees)
        results.append(CheckResult(
            id: "level", title: String(localized: "Head level"),
            detail: roll <= 3
                ? String(localized: "The eyes are level.")
                : String(localized: "The head tilts \(Int(roll.rounded()))°. Retake with your head straight."),
            status: roll <= 3 ? .pass : roll <= 6 ? .attention : .fail,
            source: .measured
        ))

        if m.faceCount > 1 {
            results.append(CheckResult(
                id: "people", title: String(localized: "Only you"),
                detail: String(localized: "\(m.faceCount) faces were found. Only the applicant can be in the photo."),
                status: .fail, source: .measured
            ))
        }
        return results
    }

    /// The background, from the measured pixels and the model's description.
    static func background(spec: PhotoSpec, stats: BackgroundStats?, observations o: PhotoObservations?) -> CheckResult {
        let need = spec.background.requirement.lowercased()
        let modelTone = o.flatMap { BackgroundTone(rawValue: $0.backgroundTone) }
        let tone = stats?.tone ?? modelTone
        let described = tone.map { String(localized: "Your background is \($0.label)") } ?? String(localized: "Your background")
        let plain = (stats?.isPlain ?? true) && (o?.backgroundIsPlain ?? true)
        let statuses = [stats.map { backgroundStatus($0.tone, rule: spec.background) },
                        modelTone.map { backgroundStatus($0, rule: spec.background) }].compactMap { $0 }
        guard !statuses.isEmpty else {
            return CheckResult(id: "background", title: String(localized: "Background"), detail: String(localized: "Needs: \(need)."), status: .pending, source: .yourself)
        }
        let status = plain ? statuses.max()! : .fail
        let detail = plain
            ? String(localized: "\(described). Needs: \(need).")
            : String(localized: "\(described) and isn’t plain: there’s a pattern, texture or something behind you. Needs: \(need).")
        return CheckResult(id: "background", title: String(localized: "Background"), detail: detail, status: status, source: o == nil ? .measured : .model)
    }

    static func observations(_ o: PhotoObservations, spec: PhotoSpec, infant: Bool = false) -> [CheckResult] {
        var results: [CheckResult] = []
        let babyEyes = infant && spec.infant?.eyesMayBeClosed == true
        let babyMouth = infant && spec.infant?.mouthMayBeOpen == true

        results.append(flag(id: "lighting", title: String(localized: "Lighting"), ok: o.lightingIsEven && !o.shadowOnFace,
                            pass: String(localized: "Even, with no shadows on the face."),
                            problem: o.shadowOnFace ? String(localized: "There are shadows on the face. Face a window or add light from the front.") : String(localized: "The face is too dark or too bright.")))
        results.append(flag(id: "shadow", title: String(localized: "No background shadow"), ok: !o.shadowOnBackground,
                            pass: String(localized: "No shadow behind you."),
                            problem: String(localized: "Your shadow shows on the background. Step away from the wall."), failing: .attention))

        let neutral = (o.expression == "neutral" || babyMouth) && (o.mouthClosed || babyMouth)
        results.append(CheckResult(
            id: "expression", title: String(localized: "Neutral expression"),
            detail: neutral ? String(localized: "Neutral, mouth closed.")
                : !o.mouthClosed ? String(localized: "The mouth is open. Close it and relax your face.")
                : String(localized: "The expression isn’t neutral. Don’t smile."),
            status: neutral ? .pass : o.expression == "slightSmile" && o.mouthClosed ? .attention : .fail,
            source: .model
        ))
        results.append(flag(id: "eyesOpen", title: String(localized: "Eyes open"), ok: (o.eyesOpen || babyEyes) && !o.faceObscured && !o.redEye,
                            pass: babyEyes && !o.eyesOpen ? String(localized: "Closed eyes are allowed for babies.") : String(localized: "Both eyes open and visible."),
                            problem: o.redEye ? String(localized: "The eyes show red-eye. Retake without flash.")
                                : o.faceObscured ? String(localized: "Hair or something else covers part of the face.") : String(localized: "Both eyes need to be open and visible.")))
        results.append(flag(id: "facing", title: String(localized: "Facing the camera"), ok: o.facingCamera,
                            pass: String(localized: "Looking straight at the camera."), problem: String(localized: "Turn to face the camera directly.")))

        let glasses = o.glasses
        let glassesStatus: CheckStatus
        let glassesDetail: String
        switch (glasses, spec.glasses) {
        case ("none", _):
            glassesStatus = .pass; glassesDetail = String(localized: "No glasses.")
        case (_, .notAllowed):
            glassesStatus = .fail; glassesDetail = String(localized: "\(spec.country) doesn’t allow glasses. Take them off.")
        case ("tinted", _):
            glassesStatus = .fail; glassesDetail = String(localized: "Tinted glasses aren’t allowed.")
        case (_, _) where o.glassesGlare:
            glassesStatus = .fail; glassesDetail = String(localized: "There’s glare on the glasses. Tilt them down slightly or take them off.")
        case (_, .discouraged):
            glassesStatus = .attention; glassesDetail = String(localized: "Glasses are discouraged. Take them off if you can.")
        default:
            glassesStatus = .pass; glassesDetail = String(localized: "Clear glasses with no glare.")
        }
        results.append(CheckResult(id: "glasses", title: String(localized: "Glasses"), detail: glassesDetail, status: glassesStatus, source: .model))

        results.append(flag(id: "headCovering", title: String(localized: "No head covering"), ok: !o.headCovering,
                            pass: String(localized: "Nothing on the head."),
                            problem: String(localized: "Remove hats and headbands. Religious or medical coverings are allowed with a statement."), failing: .attention))
        results.append(flag(id: "focus", title: String(localized: "Sharp"), ok: o.inFocus, pass: String(localized: "In focus."), problem: String(localized: "The photo is blurry. Hold still or use a tripod.")))
        results.append(flag(id: "alone", title: String(localized: "Nothing else in frame"), ok: !o.otherPeopleOrObjects,
                            pass: String(localized: "Only you in the photo."), problem: String(localized: "Someone else, a hand or an object shows in the photo.")))
        results.append(flag(id: "unedited", title: String(localized: "Unedited"), ok: !o.looksEdited,
                            pass: String(localized: "Looks unedited."), problem: String(localized: "The photo looks filtered or retouched. Use the original."), failing: .attention))
        return results
    }

    /// When no model can look at the photo, the person checks these themselves.
    static func manual(spec: PhotoSpec) -> [CheckResult] {
        [
            ("background", String(localized: "Background"), String(localized: "\(spec.background.requirement), with no shadows.")),
            ("expression", String(localized: "Neutral expression"), String(localized: "Mouth closed, both eyes open, no smile.")),
            ("glasses", String(localized: "Glasses"), String(localized: "\(spec.glasses.requirement).")),
            ("lighting", String(localized: "Lighting"), String(localized: "Even light on the face, no shadows or flash glare.")),
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
            ? (id == "head" || id == "width" ? String(localized: " Zoom in.") : id == "eyes" ? String(localized: " Move the photo up.") : String(localized: " Move the photo down."))
            : value > allowed.upperBound
            ? (id == "head" || id == "width" ? String(localized: " Zoom out.") : id == "eyes" ? String(localized: " Move the photo down.") : String(localized: " Move the photo up."))
            : ""
        return CheckResult(
            id: id, title: title,
            detail: String(localized: "\(mm(value)) \(what); needs \(allowed.formattedMM()).") + (status == .pass ? "" : hint) + extra,
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
