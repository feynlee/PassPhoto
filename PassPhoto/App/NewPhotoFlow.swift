import SwiftUI

/// How the person wants to get the photo, once they've chosen the document.
enum PhotoSourceChoice {
    case camera, library
}

/// Starting a new photo: choose the document first, see what its photo needs, then take or choose the photo.
/// With a default document set, it opens on that document; Back leads to all the others.
struct NewPhotoFlow: View {
    let onStart: (PhotoSpec, PhotoSourceChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DefaultDocument.key) private var defaultID = ""
    @State private var path: [PhotoSpec] = []

    var body: some View {
        NavigationStack(path: $path) {
            SpecList(showsChevrons: true, title: "Which Document?") { path = [$0] }
                .navigationDestination(for: PhotoSpec.self) { spec in
                    DocumentStart(spec: spec) { choice in onStart(spec, choice) }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
        }
        .onAppear {
            if let spec = SpecCatalog.spec(id: defaultID) { path = [spec] }
        }
    }
}

/// The document new photos start with, if the person picked one.
enum DefaultDocument {
    static let key = "defaultSpecID"
}

/// What a document's photo needs, and the two ways to get one.
struct DocumentStart: View {
    let spec: PhotoSpec
    let onChoose: (PhotoSourceChoice) -> Void
    @AppStorage(DefaultDocument.key) private var defaultID = ""

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text(spec.flag).font(.system(size: 48))
                    Text(spec.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(spec.sizeLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
            }

            Section {
                LabeledContent("Head, chin to \(spec.headTop == .crown ? "top of skull" : "top of hair")", value: spec.headHeightMM.formattedMM())
                LabeledContent("Background", value: spec.background.requirement)
                LabeledContent("Glasses", value: spec.glasses.requirement)
                if let kb = spec.maxFileKB {
                    LabeledContent("Upload limit", value: kb >= 1024 ? "\(kb / 1024) MB" : "\(kb) KB")
                }
                if spec.infant != nil {
                    Label("Separate rules for babies", systemImage: "figure.and.child.holdinghands")
                }
            } header: {
                Text("This Photo Needs")
            } footer: {
                Text("Neutral expression, mouth closed, eyes open, facing the camera, even light. PassPhoto crops and checks the rest.")
            }

            Section {
                VStack(spacing: 12) {
                    if CameraController.isAvailable {
                        Button { onChoose(.camera) } label: {
                            Label("Take Photo", systemImage: "camera")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button { onChoose(.library) } label: {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(CameraController.isAvailable
                     ? "For the best result, have someone else take the photo with the back camera, about 1.5 m away, in front of a plain wall."
                     : "Choose a photo taken in front of a plain wall, with the whole head and shoulders in view.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { defaultID == spec.id },
                    set: { defaultID = $0 ? spec.id : "" }
                )) {
                    Label("Default Document", systemImage: "star")
                }
            } footer: {
                Text(defaultID == spec.id
                     ? "New photos start with \(spec.title). Go back to choose another document."
                     : "Start every new photo with \(spec.title).")
            }
        }
        .navigationTitle(spec.document)
        .navigationBarTitleDisplayMode(.inline)
    }
}
