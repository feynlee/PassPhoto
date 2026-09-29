import SwiftUI

struct AboutView: View {
    @Environment(TipJar.self) private var jar
    @Environment(\.dismiss) private var dismiss
    private var updater: RequirementsUpdater { .shared }

    private var requirementsFooter: String {
        let base = String(localized: "Every requirement is re-checked against its official page each quarter, and PassPhoto downloads updates on its own. Each document links to its official page and shows when it was last confirmed.")
        switch updater.status {
        case .updated: return String(localized: "Updated to the latest requirements. ") + base
        case .upToDate: return String(localized: "You have the latest requirements. ") + base
        case .failed(let reason): return "\(reason) " + base
        default: return base
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No uploads, no account").font(.headline).foregroundStyle(Color.dsTint)
                            Text("Faces, crops and backgrounds are measured on this iPhone. Only the quality check goes to Apple’s Private Cloud Compute, which processes the photo privately and doesn’t keep it. Nothing is sent to PassPhoto or anyone else.")
                                .foregroundStyle(Color.dsInk)
                        }
                    } icon: {
                        Image(systemName: "lock.shield").foregroundStyle(Color.dsTint)
                    }
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Only what’s needed").font(.headline).foregroundStyle(Color.dsTint)
                            Text("Photos are only cropped and scaled to the official size. Background replacement is optional and off unless you turn it on. Faces are never retouched.")
                                .foregroundStyle(Color.dsInk)
                        }
                    } icon: {
                        Image(systemName: "crop").foregroundStyle(Color.dsTint)
                    }
                }

                // The tip jar, so it can be found without saving a photo first.
                Section {
                    TipSupportBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    LabeledContent("Documents", value: "\(SpecCatalog.all.count)")
                    // "XX" is the international ICAO standard, not a place; the Schengen area counts as one.
                    LabeledContent("Countries and areas", value: "\(Set(SpecCatalog.all.map(\.countryCode)).subtracting(["XX"]).count)")
                    LabeledContent("Everywhere else") { Text("ICAO standard") }
                    if let asOf = updater.asOf {
                        LabeledContent("Requirements as of", value: asOf.formatted(date: .long, time: .omitted))
                    }
                    if let lastChecked = updater.lastChecked {
                        LabeledContent("Last checked for updates", value: lastChecked.formatted(.relative(presentation: .named)))
                    }
                    Button {
                        Task { await updater.check() }
                    } label: {
                        HStack {
                            Text("Check for Updates").foregroundStyle(Color.dsTint)
                            Spacer()
                            if updater.status == .checking { ProgressView() }
                        }
                    }
                    .disabled(updater.status == .checking)
                } header: {
                    Text("Requirements").foregroundStyle(Color.dsTint)
                } footer: {
                    Text(requirementsFooter)
                }
            }
            .navigationTitle("About PassPhoto")
            .task { await jar.store.loadProducts() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
