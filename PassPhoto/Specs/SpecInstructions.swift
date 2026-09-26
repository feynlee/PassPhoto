import SwiftUI

/// One thing the person can do to meet a document's rules.
struct Instruction: Identifiable {
    let id: String
    let symbol: String
    let text: String
}

/// A document's rules split in two: instructions the person follows when taking the photo, and the
/// measurements PassPhoto takes care of, shown only as information.
enum SpecInstructions {
    static func steps(for spec: PhotoSpec, infant: Bool) -> [Instruction] {
        let baby = infant ? spec.infant : nil
        var steps: [Instruction] = []
        if baby != nil {
            steps.append(Instruction(
                id: "baby", symbol: "figure.and.child.holdinghands",
                text: "Lay your baby on a plain sheet, or support them so that no hands or arms show."
            ))
        }
        steps += [
            Instruction(id: "background", symbol: "person.and.background.dotted",
                        text: "Stand in front of a plain \(backgroundPhrase(spec.background)) wall, with nothing behind you."),
            Instruction(id: "clothes", symbol: "tshirt",
                        text: "Wear everyday clothes in a colour that stands out from the background. No uniforms."),
            Instruction(id: "glasses", symbol: "eyeglasses", text: glassesText(spec.glasses)),
            Instruction(id: "expression", symbol: "face.dashed",
                        text: baby?.mouthMayBeOpen == true
                            ? "Neutral expression. A baby’s mouth may be open."
                            : "Neutral expression with your mouth closed. Don’t smile."),
            Instruction(id: "eyes", symbol: "eye",
                        text: baby?.eyesMayBeClosed == true
                            ? "Eyes open if possible; a baby’s eyes may be closed. Look straight at the camera."
                            : "Eyes open and looking straight at the camera, with hair away from your eyes."),
            Instruction(id: "head", symbol: "person.crop.circle",
                        text: "No hat or headband. Religious or medical head coverings are fine if your whole face shows."),
            Instruction(id: "light", symbol: "sun.max",
                        text: "Face soft, even light, like a window in front of you. No shadows on your face or the wall, and no flash."),
            Instruction(id: "camera", symbol: "camera",
                        text: "Have someone else take it with the back camera, about 1.5 m away, at eye level."),
        ]
        steps += (baby?.notes ?? []).enumerated().map { Instruction(id: "babynote\($0.offset)", symbol: "info.circle", text: $0.element) }
        return steps
    }

    static func backgroundPhrase(_ background: PhotoSpec.Background) -> String {
        switch background {
        case .white: "white"
        case .whiteOrOffWhite: "white or off-white"
        case .creamOrLightGrey: "cream or light grey"
        case .lightGrey: "light grey"
        case .plainLight: "light-coloured"
        case .lightNotWhite: "light-coloured (not white)"
        case .lightBlue: "light blue"
        case .blue: "blue"
        case .red: "red"
        }
    }

    static func glassesText(_ glasses: PhotoSpec.Glasses) -> String {
        switch glasses {
        case .notAllowed: "Take off your glasses."
        case .discouraged: "Take off your glasses if you can. If you keep them on: no tint and no glare."
        case .allowed: "Glasses are fine without tint or glare, and with your eyes fully visible."
        }
    }
}

/// The instructions as a list section.
struct InstructionsSection: View {
    let spec: PhotoSpec
    let infant: Bool

    var body: some View {
        Section {
            ForEach(SpecInstructions.steps(for: spec, infant: infant)) { step in
                Label {
                    Text(step.text)
                } icon: {
                    Image(systemName: step.symbol).foregroundStyle(Color.dsTint)
                }
            }
        } header: {
            Text("How to Take It")
        }
    }
}

/// The measurements and file details, for reference. PassPhoto measures these itself.
struct SpecificationsSection: View {
    let spec: PhotoSpec
    let infant: Bool

    var body: some View {
        let head = infant ? spec.forInfant().headHeightMM : spec.headHeightMM
        Section {
            LabeledContent("Photo size", value: spec.sizeLabel)
            LabeledContent("Head, chin to top of \(spec.headTop == .crown ? "skull" : "hair")", value: head.formattedMM())
            if let eye = spec.eyeLineFromBottomMM {
                LabeledContent("Eyes from bottom edge", value: eye.formattedMM())
            }
            if let margin = spec.topMarginMM {
                LabeledContent("Space above head", value: margin.formattedMM())
            }
            if let width = spec.faceWidthMM {
                LabeledContent("Face width", value: width.formattedMM())
            }
            LabeledContent("Background", value: spec.background.requirement)
            LabeledContent("Saved as", value: "\(Int(spec.outputPixels.width)) × \(Int(spec.outputPixels.height)) px")
            if let kb = spec.maxFileKB {
                LabeledContent("Upload limit", value: kb >= 1024 ? "\(kb / 1024) MB" : "\(kb) KB")
            }
            Link(destination: spec.source) {
                Label("Official photo rules", systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("Specifications")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("PassPhoto measures and crops these for you. Checked against the official rules on \(spec.verified).")
                if spec.confidence == .partial {
                    Text("Some values come from the international standard because the issuer doesn’t publish them. Check the official rules before you submit.")
                }
                ForEach(spec.notes, id: \.self) { Text($0) }
            }
        }
    }
}
