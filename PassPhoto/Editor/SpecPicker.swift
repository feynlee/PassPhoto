import SwiftUI

/// Changes the document from inside the editor.
struct SpecPicker: View {
    let selection: PhotoSpec
    let onSelect: (PhotoSpec) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SpecList(selection: selection) { spec in
                onSelect(spec)
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }
}

/// Every document, grouped by country, with recent picks first and a search field. Used both to start a new
/// photo and to change the document in the editor.
struct SpecList: View {
    var selection: PhotoSpec?
    var showsChevrons = false
    var title: String?
    let onSelect: (PhotoSpec) -> Void

    @AppStorage("recentSpecIDs") private var recentIDs = ""
    @AppStorage(DefaultDocument.key) private var defaultID = ""
    @State private var query = ""

    private var defaultSpec: PhotoSpec? { SpecCatalog.spec(id: defaultID) }

    private var recents: [PhotoSpec] {
        recentIDs.split(separator: ",").compactMap { SpecCatalog.spec(id: String($0)) }
    }

    private var groups: [(country: String, specs: [PhotoSpec])] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return SpecCatalog.byCountry }
        return SpecCatalog.byCountry.compactMap { group in
            let matches = group.specs.filter {
                $0.title.localizedStandardContains(trimmed) || $0.sizeLabel.localizedStandardContains(trimmed)
                    || $0.countryCode.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
            }
            return matches.isEmpty ? nil : (group.country, matches)
        }
    }

    var body: some View {
        List {
            if query.isEmpty, let defaultSpec {
                Section("Default") {
                    row(defaultSpec, showCountry: true)
                }
            }
            if query.isEmpty, !recents.filter({ $0 != defaultSpec }).isEmpty {
                Section("Recent") {
                    ForEach(recents.filter { $0 != defaultSpec }) { row($0, showCountry: true) }
                }
            }
            ForEach(groups, id: \.country) { group in
                Section {
                    ForEach(group.specs) { row($0, showCountry: false) }
                } header: {
                    Text("\(group.specs[0].flag)  \(group.country)")
                }
            }
        }
        .overlay {
            if groups.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Country or document")
        .navigationTitle(title ?? "\(SpecCatalog.all.count) Photo Requirements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ spec: PhotoSpec, showCountry: Bool) -> some View {
        Button {
            remember(spec)
            onSelect(spec)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(showCountry ? "\(spec.flag)  \(spec.title)" : spec.document)
                        .foregroundStyle(.primary)
                    Text("\(spec.sizeLabel) · head \(spec.headHeightMM.formattedMM())\(spec.infant != nil ? " · baby rules" : "")\(spec.id == defaultID ? " · default" : "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if spec == selection {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.dsTint)
                } else if showsChevrons {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(spec == selection ? .isSelected : [])
        .contextMenu {
            if defaultID == spec.id {
                Button("Remove as Default", systemImage: "star.slash") { defaultID = "" }
            } else {
                Button("Set as Default", systemImage: "star") { defaultID = spec.id }
            }
        }
    }

    private func remember(_ spec: PhotoSpec) {
        let ids = [spec.id] + recentIDs.split(separator: ",").map(String.init).filter { $0 != spec.id }
        recentIDs = ids.prefix(4).joined(separator: ",")
    }
}
