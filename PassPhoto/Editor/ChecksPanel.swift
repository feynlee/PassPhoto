import SwiftUI

/// The checks in a panel that pulls up over the photo, like the Maps sheet. Collapsed, it shows a one-line
/// summary and Auto Crop, leaving the photo most of the screen; expanded, the full list.
struct ChecksPanel: View {
    let model: EditorModel
    @Binding var expanded: Bool
    let collapsedHeight: CGFloat
    let expandedHeight: CGFloat

    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { drag = $0.translation.height }
                        .onEnded { value in
                            withAnimation(.snappy) {
                                if value.translation.height < -40 { expanded = true }
                                if value.translation.height > 40 { expanded = false }
                                drag = 0
                            }
                        }
                )
                .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }

            ChecksList(model: model)
        }
        .frame(height: max(collapsedHeight, min(expandedHeight, (expanded ? expandedHeight : collapsedHeight) - drag)))
        .background(Color(uiColor: .systemGroupedBackground), in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
        .shadow(color: .black.opacity(0.18), radius: 10, y: -2)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                Image(systemName: summary.status.symbol)
                    .foregroundStyle(summary.status.color)
                    .font(.title3)
                    .accessibilityHidden(true)
                Text(summary.text)
                    .font(.headline)
                Spacer()
                Button("Auto Crop", systemImage: "wand.and.stars") {
                    withAnimation(.snappy) { model.resetToAuto() }
                }
                .buttonStyle(.bordered)
                .disabled(model.crop == model.autoCropRect)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: expanded ? "Show fewer details" : "Show all checks") {
            withAnimation(.snappy) { expanded.toggle() }
        }
    }

    private var summary: (text: String, status: CheckStatus) {
        let issues = model.openIssues
        if issues > 0 { return ("\(issues) to fix", model.checks.contains { $0.status == .fail } ? .fail : .attention) }
        if model.review == .running || model.review == .idle { return ("Checking…", .pending) }
        return ("Meets the requirements", .pass)
    }
}
