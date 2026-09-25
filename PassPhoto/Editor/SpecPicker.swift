import SwiftUI

/// Choose the country and document the photo is for.
struct SpecPicker: View {
    let selection: PhotoSpec
    let onSelect: (PhotoSpec) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("recentSpecIDs") private var recentIDs = ""
    @State private var query = ""

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
        NavigationStack {
            List {
                if query.isEmpty, !recents.isEmpty {
                    Section("Recent") {
                        ForEach(recents) { row($0, showCountry: true) }
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
            .navigationTitle("\(SpecCatalog.all.count) Photo Requirements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func row(_ spec: PhotoSpec, showCountry: Bool) -> some View {
        Button {
            remember(spec)
            onSelect(spec)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(showCountry ? "\(spec.flag)  \(spec.title)" : spec.document)
                        .foregroundStyle(.primary)
                    Text("\(spec.sizeLabel) · head \(spec.headHeightMM.formattedMM())\(spec.infant != nil ? " · baby rules" : "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if spec == selection {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.dsTint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(spec == selection ? .isSelected : [])
    }

    private func remember(_ spec: PhotoSpec) {
        let ids = [spec.id] + recentIDs.split(separator: ",").map(String.init).filter { $0 != spec.id }
        recentIDs = ids.prefix(4).joined(separator: ",")
    }
}
