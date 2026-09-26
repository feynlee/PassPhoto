import SwiftData
import SwiftUI

struct SaveSheet: View {
    let model: EditorModel
    let onSaved: (SavedSummary) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("saveToPhotos") private var toPhotos = true
    @AppStorage("keepInApp") private var inApp = true
    @AppStorage("printPaper") private var paperID = ""
    @State private var name = ""
    @State private var preview: UIImage?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        if let preview {
                            Image(uiImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .overlay { Rectangle().strokeBorder(Color(uiColor: .separator)) }
                                .accessibilityLabel("The finished photo")
                        } else {
                            ProgressView().frame(height: 200)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Name", text: $name)
                        .submitLabel(.done)
                } header: {
                    Text("Name")
                } footer: {
                    Text(fileDescription)
                }

                Section {
                    Toggle("Save to Photos", systemImage: "photo.on.rectangle", isOn: $toPhotos)
                    Toggle("Keep in PassPhoto", systemImage: "tray.full", isOn: $inApp)
                }

                if model.spec.isPrintable {
                Section {
                    Picker("Print Sheet", systemImage: "printer", selection: $paperID) {
                        Text("None").tag("")
                        ForEach(PrintSheet.Paper.allCases) { paper in
                            Text("\(paper.label) · \(PrintSheet.copies(for: model.spec, paper: paper)) copies").tag(paper.rawValue)
                        }
                    }
                } footer: {
                    Text("Copies at true size with cut marks, to print at a pharmacy or photo kiosk. Saved to Photos next to the photo.")
                }
                }

                if model.openIssues > 0 {
                    Section {
                        Label("\(model.openIssues) \(model.openIssues == 1 ? "check needs" : "checks need") a look. You can still save, but the photo may be rejected.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.dsAttention)
                    }
                }
            }
            .tint(.dsTintFill)
            .navigationTitle("Save Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!(toPhotos || inApp) || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .alert("Couldn’t Save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: {
                Text(error ?? "")
            }
            .onAppear {
                if name.isEmpty {
                    name = model.editing?.name ?? PhotoStore.defaultName(for: model.spec, date: .now)
                }
                preview = model.render().map { UIImage(cgImage: $0) }
            }
        }
        .presentationDetents([.large])
    }

    private var fileDescription: String {
        let spec = model.spec
        var text = "Saved as “\(PhotoStore.exportFileName(name: name, date: model.editing?.createdAt ?? .now))”, \(Int(spec.outputPixels.width)) × \(Int(spec.outputPixels.height)) pixels"
        if let kb = spec.maxFileKB { text += ", compressed to \(kb) KB or less for upload" }
        if model.backgroundIsReplaced { text += ". The background was replaced" }
        return text + "."
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let paper = toPhotos && model.spec.isPrintable ? PrintSheet.Paper(rawValue: paperID) : nil
            try await model.save(name: trimmed, toPhotos: toPhotos, inApp: inApp, paper: paper, context: context)
            dismiss()
            onSaved(SavedSummary(
                fileName: PhotoStore.exportFileName(name: trimmed, date: model.editing?.createdAt ?? .now),
                toPhotos: toPhotos, inApp: inApp, printSheet: paper != nil
            ))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
