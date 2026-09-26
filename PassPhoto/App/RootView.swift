import SwiftData
import SwiftUI

/// What the photo screen opens with.
enum WorkspaceStart: Identifiable {
    case new(PhotoSpec)
    case photo(EditorModel)

    var id: ObjectIdentifier {
        switch self {
        case .new: ObjectIdentifier(WorkspaceStart.self)
        case .photo(let model): ObjectIdentifier(model)
        }
    }
}

struct RootView: View {
    @Query(sort: \SavedPhoto.createdAt, order: .reverse) private var photos: [SavedPhoto]
    @AppStorage("lastSpecID") private var lastSpecID = SpecCatalog.fallback.id
    @AppStorage(DefaultDocument.key) private var defaultID = ""
    @State private var workspace: WorkspaceStart?
    @State private var loadError: String?
    @State private var showingAbout = false

    /// New photos start on the default document, else the last one used.
    private var startSpec: PhotoSpec {
        SpecCatalog.spec(id: defaultID) ?? SpecCatalog.spec(id: lastSpecID) ?? SpecCatalog.fallback
    }

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    ContentUnavailableView {
                        Label("No Photos Yet", systemImage: "person.crop.square")
                    } description: {
                        Text("Tap + to make a passport, visa or ID photo for any of \(SpecCatalog.all.count) documents. Your photo never goes to a company server, and there’s no account.")
                    }
                } else {
                    PhotoLibraryList(photos: photos) { photo in open(photo) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // The one way to start, in the same place whether or not there are saved photos.
                Button { workspace = .new(startSpec) } label: {
                    Image(systemName: "plus")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.dsTintFill, in: .circle)
                        .overlay { Circle().strokeBorder(.white.opacity(0.15)) }
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Photo")
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
        .fullScreenCover(item: $workspace) { start in
            switch start {
            case .new(let spec): PhotoWorkspace(spec: spec)
            case .photo(let model): PhotoWorkspace(model: model)
            }
        }
        .sheet(isPresented: $showingAbout) { AboutView() }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-demoEditor") {
                let model = EditorModel(image: DemoPhoto.image(), spec: startSpec)
                model.presetMeasurement = DemoPhoto.measurement
                workspace = .photo(model)
            }
        }
        #endif
        .alert("Can’t Open Photo", isPresented: Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
            Button("OK") {}
        } message: {
            Text(loadError ?? "")
        }
    }

    private func open(_ photo: SavedPhoto) {
        guard let original = UIImage(contentsOfFile: photo.originalURL.path(percentEncoded: false))?.cgImage else {
            loadError = "The original of this photo is missing, so it can’t be adjusted."
            return
        }
        workspace = .photo(EditorModel(image: original, spec: photo.spec, editing: photo))
    }
}
