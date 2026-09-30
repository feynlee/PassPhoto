import SwiftUI

/// The requirements, each with its result: measurements update live while panning and zooming; the photo
/// quality checks come from Private Cloud Compute (or the on-device model).
struct ChecksList: View {
    let model: EditorModel

    var body: some View {
        @Bindable var model = model
        List {
            if model.spec.infant != nil {
                Section {
                    Toggle(isOn: $model.isInfant) {
                        Label(babyLabel, systemImage: "figure.and.child.holdinghands")
                    }
                }
            }

            if let acceptance = model.acceptanceCheck {
                Section { CheckRow(check: acceptance) }
            }

            Section {
                ForEach(model.measuredChecks) { CheckRow(check: $0) }
                if let background = model.backgroundCheck { CheckRow(check: background) }
            } header: {
                Text("Measurements").foregroundStyle(Color.dsTint)
            } footer: {
                Text("Measured on this iPhone. Only cropping and scaling are applied; the photo itself isn’t changed.")
            }

            Section {
                switch model.review {
                case .idle, .running:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking with Private Cloud Compute…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                case .done, .unavailable:
                    ForEach(model.modelChecks) { CheckRow(check: $0) }
                }
            } header: {
                Text("Photo Quality").foregroundStyle(Color.dsTint)
            } footer: {
                switch model.review {
                case .done(_, let engine):
                    Text("Checked by the \(engine.label). The photo is processed privately and isn’t stored.")
                case .unavailable(let reason):
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(reason) Check these yourself.")
                        Button("Try Again") { Task { await model.runReview() } }
                            .font(.footnote.weight(.semibold))
                    }
                default:
                    EmptyView()
                }
            }

            InstructionsSection(spec: model.spec, infant: model.isInfant)
            SpecificationsSection(spec: model.spec, infant: model.isInfant)
        }
        .listStyle(.insetGrouped)
        .tint(.dsTintFill)
    }
}

private extension ChecksList {
    var babyLabel: String {
        if let months = model.spec.infant?.maxAgeMonths { return String(localized: "Baby under \(months) months") }
        return String(localized: "Baby")
    }

}

struct CheckRow: View {
    let check: CheckResult

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: check.status.symbol)
                .foregroundStyle(check.status.color)
                .font(.body)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.body.weight(.medium))
                Text(check.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityStatus)
    }

    private var accessibilityStatus: String {
        switch check.status {
        case .pass: String(localized: "Passes")
        case .attention: String(localized: "Needs a look")
        case .fail: String(localized: "Doesn’t meet the requirement")
        case .pending: String(localized: "Check yourself")
        }
    }
}
