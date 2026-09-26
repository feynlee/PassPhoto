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
    @Environment(TipJar.self) private var jar

    /// New photos start on the default document, else the last one used.
    private var startSpec: PhotoSpec {
        SpecCatalog.spec(id: defaultID) ?? SpecCatalog.spec(id: lastSpecID) ?? SpecCatalog.fallback
    }

    var body: some View {
        ZStack {
            library
            overlays
        }
    }

    /// The saved-photo card with the tip jar, the thank-you after a tip, and the celebration, above everything.
    @ViewBuilder
    private var overlays: some View {
        if let summary = jar.saved {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy) { jar.saved = nil } }
                .transition(.opacity)
            VStack {
                Spacer()
                SavedConfirmationCard(summary: summary)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        if jar.showsThanks {
            Color.black.opacity(0.35).ignoresSafeArea().transition(.opacity)
            TipThanksCard().transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        if let celebration = jar.celebration {
            CelebrationView(celebration: celebration) { jar.celebrationFinished(celebration.id) }
                .id(celebration.id)
        }
    }

    private var library: some View {
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
            case .new(let spec): PhotoWorkspace(spec: spec).foregroundStyle(Color.dsInk)
            case .photo(let model): PhotoWorkspace(model: model).foregroundStyle(Color.dsInk)
            }
        }
        .sheet(isPresented: $showingAbout) { AboutView().foregroundStyle(Color.dsInk) }
        .animation(.snappy, value: jar.saved)
        .animation(.snappy, value: jar.showsThanks)
        #if DEBUG
        .task {
            if let style = UserDefaults.standard.string(forKey: "celebrate").flatMap(CelebrationStyle.init(rawValue:)) {
                try? await Task.sleep(for: .seconds(1))
                jar.celebrate(style)
            }
            if ProcessInfo.processInfo.arguments.contains("-demoSaved") {
                jar.saved = SavedSummary(fileName: "United States Passport 2026-09-26 09.30.jpg", toPhotos: true, inApp: true, printSheet: true)
            }
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
