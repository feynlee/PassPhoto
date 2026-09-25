import SwiftData
import SwiftUI

struct EditorView: View {
    @State var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastSpecID") private var lastSpecID = SpecCatalog.fallback.id
    @State private var choosingSpec = false
    @State private var saving = false
    @State private var checksExpanded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                specButton
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
                    GeometryReader { proxy in
                        let collapsed: CGFloat = 132
                        ZStack(alignment: .bottom) {
                            CropCanvas(model: model)
                                .frame(height: proxy.size.height - collapsed + 20)
                                .frame(maxHeight: .infinity, alignment: .top)
                            ChecksPanel(
                                model: model, expanded: $checksExpanded,
                                collapsedHeight: collapsed, expandedHeight: proxy.size.height * 0.75
                            )
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(model.editing == nil ? "New Photo" : "Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saving = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.phase != .ready)
                }
            }
            .sheet(isPresented: $choosingSpec) {
                SpecPicker(selection: model.spec) { spec in
                    withAnimation(.snappy) { model.select(spec) }
                    lastSpecID = spec.id
                }
            }
            .sheet(isPresented: $saving) {
                SaveSheet(model: model) { dismiss() }
            }
            .task { await model.start() }
        }
    }

    private var specButton: some View {
        Button { choosingSpec = true } label: {
            HStack(spacing: 12) {
                Text(model.spec.flag)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.spec.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(model.spec.sizeLabel) · head \(model.spec.headHeightMM.formattedMM())")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Requirements: \(model.spec.title), \(model.spec.sizeLabel)")
        .accessibilityHint("Choose another country or document")
    }
}
