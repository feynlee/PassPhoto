import SwiftData
import SwiftUI

struct SavedPhotoDetail: View {
    let photo: SavedPhoto
    let onAdjust: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var message: String?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .overlay { Rectangle().strokeBorder(Color(uiColor: .separator), lineWidth: 0.5) }
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxHeight: 320)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .accessibilityLabel("The saved photo")
            }

            Section {
                LabeledContent("For", value: "\(photo.spec.flag) \(photo.spec.title)")
                LabeledContent("Size", value: photo.spec.sizeLabel)
                LabeledContent("Pixels", value: "\(photo.pixelWidth) × \(photo.pixelHeight)")
                LabeledContent("Created", value: photo.createdAt.formatted(date: .long, time: .shortened))
                LabeledContent("File name", value: photo.exportFileName)
                if photo.backgroundReplaced {
                    LabeledContent("Background", value: "Replaced")
                }
                if photo.isInfant {
                    LabeledContent("Rules", value: "Baby")
                }
                if photo.openIssues > 0 {
                    Label("\(photo.openIssues) \(photo.openIssues == 1 ? "check needed" : "checks needed") a look when saved.", systemImage: CheckStatus.attention.symbol)
                        .foregroundStyle(Color.dsAttention)
                }
            }

            Section {
                ShareLink(item: SharedPhotoFile(photo: photo), preview: SharePreview(photo.name)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Menu {
                    ForEach(PrintSheet.Paper.allCases) { paper in
                        ShareLink(item: PrintSheetFile(photo: photo, paper: paper), preview: SharePreview("\(photo.name), print sheet")) {
                            Text("\(paper.label) · \(PrintSheet.copies(for: photo.spec, paper: paper)) copies")
                        }
                    }
                } label: {
                    Label("Print Sheet", systemImage: "printer")
                }
                Button("Save to Photos", systemImage: "square.and.arrow.down") {
                    Task { message = await PhotoLibraryList.saveToPhotos(photo) }
                }
                Button("Adjust Crop or Country", systemImage: "crop", action: onAdjust)
                Button("Rename", systemImage: "pencil") {
                    newName = photo.name
                    renaming = true
                }
            }

            Section {
                Button("Delete Photo", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(photo.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: photo.fileName) {
            image = UIImage(contentsOfFile: photo.fileURL.path(percentEncoded: false))
        }
        .alert("Rename Photo", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { photo.name = trimmed }
            }
        }
        .confirmationDialog("Delete “\(photo.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) {
                dismiss()
                PhotoLibraryList.delete(photo, in: context)
            }
        } message: {
            Text("Copies you saved to Photos stay there.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        }
    }
}
