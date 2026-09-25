import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No uploads, no account").font(.headline)
                            Text("Faces, crops and backgrounds are measured on this iPhone. Only the quality check goes to Apple’s Private Cloud Compute, which processes the photo privately and doesn’t keep it. Nothing is sent to PassPhoto or anyone else.")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield").foregroundStyle(Color.dsTint)
                    }
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Only what’s needed").font(.headline)
                            Text("Photos are cropped and scaled. The background is replaced only when it breaks the rules, and you can turn that off. Faces are never retouched.")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "crop").foregroundStyle(Color.dsTint)
                    }
                }

                Section {
                    LabeledContent("Documents", value: "\(SpecCatalog.all.count)")
                    LabeledContent("Countries", value: "\(Set(SpecCatalog.all.map(\.countryCode)).count)")
                } header: {
                    Text("Requirements")
                } footer: {
                    Text("Each requirement links to the official page it came from and shows when it was checked. Rules change; check the official page before you submit.")
                }
            }
            .navigationTitle("About PassPhoto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
