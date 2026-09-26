import PhotosUI
import SwiftData
import SwiftUI

/// The one screen for making a photo. The document picker is always at the top. Before there's a photo it
/// shows how to take one and the two ways to add it; after, the photo with its guides, Auto Crop above it,
/// and a status bar below that opens every check.
struct PhotoWorkspace: View {
    @State private var spec: PhotoSpec
    @State private var localInfant = false
    @State private var model: EditorModel?

    @Environment(\.dismiss) private var dismiss
    @Environment(TipJar.self) private var jar
    @AppStorage("lastSpecID") private var lastSpecID = SpecCatalog.fallback.id
    @AppStorage(DefaultDocument.key) private var defaultID = ""
    @State private var choosingSpec = false
    @State private var takingPhoto = false
    @State private var choosingPhoto = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var captured: UIImage?
    @State private var showingChecks = false
    @State private var saving = false
    @State private var loadError: String?

    /// Starts without a photo, on `spec`.
    init(spec: PhotoSpec) {
        _spec = State(initialValue: spec)
    }

    /// Starts with a photo already loaded (adjusting a saved photo, or the demo).
    init(model: EditorModel) {
        _spec = State(initialValue: model.spec)
        _model = State(initialValue: model)
    }

    private var infant: Binding<Bool> {
        if let model {
            Binding(get: { model.isInfant }, set: { model.isInfant = $0 })
        } else {
            $localInfant
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DocumentCard(spec: spec, isDefault: defaultID == spec.id) {
                    choosingSpec = true
                } toggleDefault: {
                    defaultID = defaultID == spec.id ? "" : spec.id
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                if let model {
                    photoArea(model)
                        // Measure each new photo once it's on screen.
                        .task(id: ObjectIdentifier(model)) { await model.start() }
                } else {
                    instructions
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(model?.editing == nil ? "New Photo" : "Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                if let model {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saving = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.dsTintFill)
                            .disabled(model.phase != .ready)
                    }
                }
            }
            .sheet(isPresented: $choosingSpec) {
                SpecPicker(selection: spec) { newSpec in
                    withAnimation(.snappy) { select(newSpec) }
                }
            }
            .sheet(isPresented: $showingChecks) {
                if let model {
                    NavigationStack {
                        ChecksList(model: model)
                            .navigationTitle("Checks")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showingChecks = false }
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Color(uiColor: .systemGroupedBackground))
                }
            }
            .sheet(isPresented: $saving) {
                if let model {
                    SaveSheet(model: model) { summary in
                        jar.photoSaved(summary)
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $takingPhoto, onDismiss: {
                if let captured { load(captured) }
                captured = nil
            }) {
                GuidedCameraView { captured = $0 }
            }
            .photosPicker(isPresented: $choosingPhoto, selection: $pickerItem, matching: .images, preferredItemEncoding: .current)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                pickerItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        loadError = "That photo couldn’t be read."
                        return
                    }
                    load(image)
                }
            }
            .alert("Can’t Open Photo", isPresented: Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
                Button("OK") {}
            } message: {
                Text(loadError ?? "")
            }
            .task {
                // With no default and nothing used before, start by choosing the document.
                if model == nil, defaultID.isEmpty, UserDefaults.standard.string(forKey: "lastSpecID") == nil {
                    choosingSpec = true
                }
            }
        }
    }

    // MARK: Before a photo

    private var instructions: some View {
        List {
            SpecNoticesSection(spec: spec)
            if spec.infant != nil {
                Section {
                    Toggle(isOn: infant) {
                        Label(babyLabel, systemImage: "figure.and.child.holdinghands")
                    }
                } footer: {
                    Text("\(spec.country) has separate rules for babies. Turn this on to use them for the instructions, guides and checks.")
                }
            }

            InstructionsSection(spec: spec, infant: infant.wrappedValue)
            SpecificationsSection(spec: spec, infant: infant.wrappedValue)
        }
        .listStyle(.insetGrouped)
        // The two ways to add the photo stay at the bottom, floating over the instructions as they scroll.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SourceButtons(takePhoto: { takingPhoto = true }, chooseFromLibrary: { choosingPhoto = true })
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background {
                    // A solid backing, so text never shows through the buttons, with a short fade above it
                    // where the list scrolls away.
                    let ground = Color(uiColor: .systemGroupedBackground)
                    VStack(spacing: 0) {
                        LinearGradient(colors: [ground.opacity(0), ground], startPoint: .top, endPoint: .bottom)
                            .frame(height: 28)
                        ground
                    }
                    .padding(.top, -28)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                }
        }
    }

    private var babyLabel: String {
        if let months = spec.infant?.maxAgeMonths { return "Baby under \(months) months" }
        return "Photo of a baby"
    }

    // MARK: With a photo

    private func photoArea(_ model: EditorModel) -> some View {
        VStack(spacing: 0) {
        HStack {
            Button("Auto Crop", systemImage: "wand.and.stars") {
                withAnimation(.snappy) { model.resetToAuto() }
            }
            .buttonStyle(.bordered)
            .disabled(model.phase != .ready || model.crop == model.autoCropRect)
            Spacer()
            Menu {
                if CameraController.isAvailable {
                    Button("Take Photo", systemImage: "camera") { takingPhoto = true }
                }
                Button("Choose from Library", systemImage: "photo.on.rectangle") { choosingPhoto = true }
            } label: {
                Label("Replace Photo", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)

        switch model.phase {
        case .measuring:
            ZStack {
                Color.black
                ProgressView("Finding your face…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Can’t Fit This Photo", systemImage: "person.crop.square.badge.camera", description: Text(message))
                .frame(maxHeight: .infinity)
        case .ready:
            CropCanvas(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            StatusBar(model: model) { showingChecks = true }
        }
        }
    }

    // MARK: Actions

    private func select(_ newSpec: PhotoSpec) {
        spec = newSpec
        lastSpecID = newSpec.id
        if newSpec.infant == nil { localInfant = false }
        model?.select(newSpec)
    }

    private func load(_ image: UIImage) {
        guard let normalized = PhotoRenderer.normalized(image) else {
            loadError = "That photo couldn’t be read."
            return
        }
        lastSpecID = spec.id
        withAnimation(.snappy) {
            model = EditorModel(image: normalized, spec: spec, infant: infant.wrappedValue, editing: model?.editing)
        }
    }
}

/// The chosen document, tappable to change it, with a star to make it the default.
private struct DocumentCard: View {
    let spec: PhotoSpec
    let isDefault: Bool
    let change: () -> Void
    let toggleDefault: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: change) {
                HStack(spacing: 12) {
                    Text(spec.flag).font(.title2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(spec.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(spec.sizeLabel) · rules as of \(spec.verifiedLabel)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Document: \(spec.title), \(spec.sizeLabel), requirements as of \(spec.verifiedLabel)")
            .accessibilityHint("Choose another country or document")

            Button(action: toggleDefault) {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.dsTint)
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDefault ? "Default document" : "Make default document")
            .accessibilityAddTraits(isDefault ? .isSelected : [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }
}

/// Take Photo and Choose from Library, full width, text centred with its icon.
struct SourceButtons: View {
    let takePhoto: () -> Void
    let chooseFromLibrary: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if CameraController.isAvailable {
                Button(action: takePhoto) {
                    centred("Take Photo", systemImage: "camera.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.dsTintFill)
            }
            Button(action: chooseFromLibrary) {
                centred("Choose from Library", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private func centred(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Whether the photo meets the document's rules, tappable for every check.
private struct StatusBar: View {
    let model: EditorModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: summary.status.symbol)
                    .font(.title3)
                    .foregroundStyle(summary.status.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.text)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("See all checks")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .accessibilityHint("Shows every requirement and whether the photo meets it")
    }

    private var summary: (text: String, status: CheckStatus) {
        let issues = model.openIssues
        if issues > 0 {
            return ("\(issues) \(issues == 1 ? "thing" : "things") to fix", model.checks.contains { $0.status == .fail } ? .fail : .attention)
        }
        if model.review == .running || model.review == .idle { return ("Checking the photo…", .pending) }
        return ("Meets every requirement", .pass)
    }
}

/// The document new photos start with, if the person picked one.
enum DefaultDocument {
    static let key = "defaultSpecID"
}
