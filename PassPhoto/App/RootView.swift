import PhotosUI
import SwiftData
import SwiftUI

/// A photo on its way into the editor.
struct EditorSource: Identifiable {
    let id = UUID()
    let image: CGImage
    let spec: PhotoSpec
    var editing: SavedPhoto?
    var isDemo = false
}

struct RootView: View {
    @Query(sort: \SavedPhoto.createdAt, order: .reverse) private var photos: [SavedPhoto]
    @AppStorage("lastSpecID") private var lastSpecID = SpecCatalog.fallback.id
    @State private var takingPhoto = false
    @State private var choosingPhoto = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var source: EditorSource?
    @State private var loadError: String?
    @State private var captured: UIImage?
    @State private var showingAbout = false
    @State private var startingNewPhoto = false
    /// What the new-photo flow picked, acted on once its sheet is gone.
    @State private var pendingStart: (spec: PhotoSpec, choice: PhotoSourceChoice)?
    /// The document the photo being taken or chosen is for.
    @State private var chosenSpec: PhotoSpec?

    private var lastSpec: PhotoSpec { SpecCatalog.spec(id: lastSpecID) ?? SpecCatalog.fallback }

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    emptyState
                } else {
                    PhotoLibraryList(photos: photos) { photo in open(photo) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // The one way to start: the same button whether or not there are saved photos.
                Button { startingNewPhoto = true } label: {
                    Label("New Photo", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .padding(.bottom, 8)
            }
            .navigationTitle("PassPhoto")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("About", systemImage: "info.circle") { showingAbout = true }
                }
            }
            .navigationDestination(for: SavedPhoto.self) { photo in
                SavedPhotoDetail(photo: photo) { open(photo) }
            }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $pickerItem, matching: .images, preferredItemEncoding: .current)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { await load(item) }
        }
        .fullScreenCover(isPresented: $takingPhoto, onDismiss: {
            // Open the editor only once the camera is gone; two covers can't present at once.
            if let captured { edit(captured) }
            captured = nil
        }) {
            GuidedCameraView { image in captured = image }
        }
        .fullScreenCover(item: $source) { source in
            EditorView(model: makeModel(for: source))
        }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .sheet(isPresented: $startingNewPhoto, onDismiss: {
            // Open the camera or library only once the sheet is gone.
            guard let pendingStart else { return }
            self.pendingStart = nil
            chosenSpec = pendingStart.spec
            lastSpecID = pendingStart.spec.id
            switch pendingStart.choice {
            case .camera: takingPhoto = true
            case .library: choosingPhoto = true
            }
        }) {
            NewPhotoFlow { spec, choice in
                pendingStart = (spec, choice)
                startingNewPhoto = false
            }
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-demoEditor") {
                source = EditorSource(image: DemoPhoto.image(), spec: lastSpec, isDemo: true)
            }
        }
        #endif
        .alert("Can’t Open Photo", isPresented: Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
            Button("OK") {}
        } message: {
            Text(loadError ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Photos Yet", systemImage: "person.crop.square")
        } description: {
            Text("Tap New Photo, choose your document, then take or choose a photo. PassPhoto fits it to the passport, visa or ID rules of \(SpecCatalog.all.count) documents and checks it with Private Cloud Compute. Your photo never goes to a company server, and there’s no account.")
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            loadError = "That photo couldn’t be read."
            return
        }
        edit(image)
    }

    private func edit(_ image: UIImage) {
        guard let normalized = PhotoRenderer.normalized(image) else {
            loadError = "That photo couldn’t be read."
            return
        }
        source = EditorSource(image: normalized, spec: chosenSpec ?? lastSpec)
    }

    private func makeModel(for source: EditorSource) -> EditorModel {
        let model = EditorModel(image: source.image, spec: source.spec, editing: source.editing)
        #if DEBUG
        if source.isDemo { model.presetMeasurement = DemoPhoto.measurement }
        #endif
        return model
    }

    private func open(_ photo: SavedPhoto) {
        guard let original = UIImage(contentsOfFile: photo.originalURL.path(percentEncoded: false))?.cgImage else {
            loadError = "The original of this photo is missing, so it can’t be adjusted."
            return
        }
        source = EditorSource(image: original, spec: photo.spec, editing: photo)
    }
}
