import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Saved photos, newest first, each with its name, requirement and date.
struct PhotoLibraryList: View {
    let photos: [SavedPhoto]
    let onAdjust: (SavedPhoto) -> Void

    @Environment(\.modelContext) private var context
    @State private var renaming: SavedPhoto?
    @State private var newName = ""
    @State private var deleting: SavedPhoto?
    @State private var message: String?

    var body: some View {
        List {
            ForEach(photos) { photo in
                NavigationLink(value: photo) {
                    SavedPhotoRow(photo: photo)
                }
                .contextMenu {
                    ShareLink(item: SharedPhotoFile(photo: photo), preview: SharePreview(photo.name))
                    Button("Save to Photos", systemImage: "square.and.arrow.down") { Task { await saveToPhotos(photo) } }
                    Button("Adjust", systemImage: "crop") { onAdjust(photo) }
                    Button("Rename", systemImage: "pencil") { startRenaming(photo) }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = photo }
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = photo }
                    Button("Rename", systemImage: "pencil") { startRenaming(photo) }
                }
            }
        }
        .alert("Rename Photo", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if let renaming, !trimmed.isEmpty { renaming.name = trimmed }
            }
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Photo", role: .destructive) {
                if let deleting { PhotoLibraryList.delete(deleting, in: context) }
            }
        } message: {
            Text("Copies you saved to Photos stay there.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        }
    }

    private func startRenaming(_ photo: SavedPhoto) {
        newName = photo.name
        renaming = photo
    }

    private func saveToPhotos(_ photo: SavedPhoto) async {
        message = await PhotoLibraryList.saveToPhotos(photo)
    }

    /// Returns what to tell the person.
    static func saveToPhotos(_ photo: SavedPhoto) async -> String {
        do {
            let data = try Data(contentsOf: photo.fileURL)
            try await PhotoLibrarySaver.save(data, fileName: photo.exportFileName)
            return "Saved to Photos"
        } catch {
            return error.localizedDescription
        }
    }

    static func delete(_ photo: SavedPhoto, in context: ModelContext) {
        PhotoStore.remove([photo.fileName, photo.originalFileName])
        context.delete(photo)
        try? context.save()
    }
}

struct SavedPhotoRow: View {
    let photo: SavedPhoto

    var body: some View {
        HStack(spacing: 14) {
            PhotoThumbnail(url: photo.fileURL, aspect: photo.spec.aspect)
                .frame(width: 52, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(photo.name)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(photo.spec.flag) \(photo.spec.sizeLabel) · \(photo.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if photo.openIssues > 0 {
                    Label("\(photo.openIssues) to review", systemImage: CheckStatus.attention.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.dsAttention)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// A saved photo's JPEG, loaded off the main thread.
struct PhotoThumbnail: View {
    let url: URL
    let aspect: Double
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay { Rectangle().strokeBorder(Color(uiColor: .separator), lineWidth: 0.5) }
            } else {
                Rectangle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .aspectRatio(aspect, contentMode: .fit)
            }
        }
        .task(id: url) {
            image = await Self.load(url)
        }
        .accessibilityHidden(true)
    }

    @concurrent
    nonisolated private static func load(_ url: URL) async -> UIImage? {
        UIImage(contentsOfFile: url.path(percentEncoded: false))?.preparingThumbnail(of: CGSize(width: 240, height: 240))
    }
}

/// A saved photo shared under its clear name rather than its storage name.
nonisolated struct SharedPhotoFile: Transferable {
    let source: URL
    let fileName: String

    @MainActor
    init(photo: SavedPhoto) {
        source = photo.fileURL
        fileName = photo.exportFileName
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jpeg) { file in
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(path: file.fileName)
            try FileManager.default.copyItem(at: file.source, to: copy)
            return SentTransferredFile(copy)
        }
    }
}

/// A print sheet made from a saved photo, rendered when it's shared.
nonisolated struct PrintSheetFile: Transferable {
    let source: URL
    let spec: PhotoSpec
    let paper: PrintSheet.Paper
    let fileName: String

    @MainActor
    init(photo: SavedPhoto, paper: PrintSheet.Paper) {
        source = photo.fileURL
        spec = photo.spec
        self.paper = paper
        fileName = PhotoStore.exportFileName(name: photo.name, date: photo.createdAt, suffix: "print \(paper.fileLabel)")
    }

    enum RenderError: Error { case failed }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jpeg) { file in
            guard let photo = UIImage(contentsOfFile: file.source.path(percentEncoded: false))?.cgImage,
                  let sheet = PrintSheet.render(photo, spec: file.spec, paper: file.paper),
                  let data = PhotoRenderer.jpegData(sheet, dpi: PrintSheet.dpi) else { throw RenderError.failed }
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: file.fileName)
            try data.write(to: url)
            return SentTransferredFile(url)
        }
    }
}
