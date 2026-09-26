import StoreKit
import SwiftUI

/// App-wide state for the tip jar and its celebrations.
@Observable
final class TipJar {
    let store = TipStore()
    /// Shown after a photo is saved: the confirmation card with the tip jar.
    var saved: SavedSummary?
    /// The thank-you card right after a tip.
    var showsThanks = false
    private(set) var celebration: Celebration?

    /// Plays the tipper's chosen celebration, unless they've turned it off.
    func celebrate(_ style: CelebrationStyle? = nil) {
        let style = style ?? store.celebrationStyle
        guard style != .off else { return }
        celebration = Celebration(style: style)
    }

    func celebrationFinished(_ id: Celebration.ID) {
        if celebration?.id == id { celebration = nil }
    }

    /// A photo was saved: confirm it, and celebrate for people who tipped.
    func photoSaved(_ summary: SavedSummary) {
        saved = summary
        guard store.hasTipped else { return }
        // Start once the photo screen has slid away, so the celebration isn't hidden behind it.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            celebrate()
        }
    }
}

/// What was just saved, for the confirmation.
struct SavedSummary: Equatable {
    let fileName: String
    let toPhotos: Bool
    let inApp: Bool
    let printSheet: Bool
}

/// The card that slides up after saving: where the photo went, then the tip jar.
struct SavedConfirmationCard: View {
    @Environment(TipJar.self) private var jar
    let summary: SavedSummary

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.dsTint)
                .padding(.top, 24)
            Text("Photo Saved")
                .font(.title2.weight(.bold))
                .padding(.top, 10)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 6)

            if !jar.store.options.isEmpty {
                TipSupportBanner()
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
            }

            Button {
                withAnimation(.snappy) { jar.saved = nil }
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.dsTintFill)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .frame(maxWidth: 500)
        .background(Color(uiColor: .systemGroupedBackground), in: .rect(cornerRadius: 32))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
        .padding(.horizontal, 10)
        .task { await jar.store.loadProducts() }
    }

    private var detail: String {
        var parts: [String] = []
        if summary.toPhotos { parts.append(summary.printSheet ? "saved to Photos with a print sheet" : "saved to Photos") }
        if summary.inApp { parts.append("kept in PassPhoto") }
        return "“\(summary.fileName)” was \(parts.joined(separator: ", and "))."
    }
}

/// Buy Me a Coffee, as in BillSplit: three quick amounts and a custom one. After a tip it collapses to a
/// thank-you with the total given; tapping it shows the tip options and the celebration choice again.
struct TipSupportBanner: View {
    @Environment(TipJar.self) private var jar
    @State private var heartBeat = 0
    @State private var textHeight: CGFloat = 40
    @State private var showsMore = false

    var body: some View {
        let tips = jar.store
        let accent: Color = tips.hasTipped ? CelebrationFrame.pink : .orange
        let showsOptions = !tips.hasTipped || showsMore

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accent.opacity(0.15))
                    .overlay {
                        Image(systemName: tips.hasTipped ? "heart.fill" : "cup.and.saucer.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(accent)
                            .padding(textHeight * 0.14)
                            .symbolEffect(.bounce, value: heartBeat)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: textHeight, height: textHeight)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tips.hasTipped ? "Thanks for your support!" : "Buy Me a Coffee")
                        .font(.headline)
                    Text(tips.hasTipped ? "You’ve given \(tips.formattedTotal) so far." : "Enjoying PassPhoto? A tip is appreciated.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { textHeight = $0 }

                if tips.hasTipped {
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showsMore ? 180 : 0))
                        .frame(height: textHeight)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                guard tips.hasTipped else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showsMore.toggle() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(tips.hasTipped ? .isButton : [])
            .accessibilityHint(tips.hasTipped ? (showsMore ? "Hides the tip options" : "Shows options for another tip") : "")

            if showsOptions {
                VStack(alignment: .leading, spacing: 10) {
                    if tips.hasTipped {
                        Text("Another coffee?")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    TipOptions()
                    if tips.hasTipped {
                        Divider().padding(.top, 4)
                        CelebrationPicker()
                    }
                }
                .padding(.top, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tips.tipCount)
        .onChange(of: tips.tipCount) {
            heartBeat += 1
            showsMore = false
            jar.showsThanks = true
        }
        .sensoryFeedback(.success, trigger: tips.tipCount)
    }
}

/// Three quick amounts, plus Custom: the smallest tip bought 1–10 times, chosen with a stepper.
struct TipOptions: View {
    @Environment(TipJar.self) private var jar
    @State private var showsCustom = false
    @State private var quantity = 3

    var body: some View {
        let tips = jar.store
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(tips.options) { option in
                    Button { buy(option, quantity: 1) } label: {
                        ZStack {
                            Text(option.displayPrice()).opacity(isBuying(option, 1) ? 0 : 1)
                            if isBuying(option, 1) { ProgressView() }
                        }
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel("Tip \(option.displayPrice())")
                }
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showsCustom.toggle() }
                } label: {
                    Text("Custom")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TipChipStyle(selected: showsCustom))
                .accessibilityAddTraits(showsCustom ? .isSelected : [])
            }
            .buttonStyle(TipChipStyle(selected: false))
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            if showsCustom, let unit = tips.smallest {
                customRow(unit)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .disabled(tips.isPurchasing)
    }

    private func customRow(_ unit: TipStore.Option) -> some View {
        HStack(spacing: 12) {
            Stepper(value: $quantity, in: TipStore.quantityRange) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(unit.displayPrice(quantity: quantity))
                        .font(.title3.monospacedDigit().weight(.bold))
                        .contentTransition(.numericText(value: Double(quantity)))
                    Text("\(quantity) × \(unit.displayPrice())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Button { buy(unit, quantity: quantity) } label: {
                ZStack {
                    Text("Tip").opacity(isBuying(unit, quantity) && quantity > 1 ? 0 : 1)
                    if isBuying(unit, quantity), quantity > 1 { ProgressView().tint(.white) }
                }
                .font(.subheadline.weight(.bold))
                .frame(width: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.dsTintFill)
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .animation(.snappy, value: quantity)
    }

    private func isBuying(_ option: TipStore.Option, _ quantity: Int) -> Bool {
        guard let purchasing = jar.store.purchasing else { return false }
        return purchasing.id == option.id && purchasing.quantity == quantity
    }

    private func buy(_ option: TipStore.Option, quantity: Int) {
        Task { await jar.store.purchase(option, quantity: quantity) }
    }
}

/// Tippers choose how saving a photo celebrates; tapping a style previews it.
struct CelebrationPicker: View {
    @Environment(TipJar.self) private var jar

    var body: some View {
        @Bindable var store = jar.store
        VStack(alignment: .leading, spacing: 8) {
            Text("Celebration when you save")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(CelebrationStyle.allCases) { style in
                    let selected = store.celebrationStyle == style
                    Button {
                        store.celebrationStyle = style
                        jar.celebrate(style)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: style.symbol).font(.title3)
                            Text(style == .off ? "Off" : style.label.components(separatedBy: " ").last ?? style.label)
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(selected ? Color.dsOnTint : .primary)
                        .background(selected ? Color.dsTint : Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// Right after a tip: thank you, the total given, and a first celebration, which they can change.
struct TipThanksCard: View {
    @Environment(TipJar.self) private var jar
    @State private var heartBeat = 0

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 20)
                .fill(CelebrationFrame.pink.opacity(0.15))
                .frame(width: 76, height: 76)
                .overlay {
                    Image(systemName: "heart.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(CelebrationFrame.pink)
                        .padding(17)
                        .symbolEffect(.bounce, value: heartBeat)
                }
                .accessibilityHidden(true)

            Text("Thank you!")
                .font(.title2.weight(.bold))
                .padding(.top, 14)
            Text("Your coffee means a lot. As a thank-you, every photo you save now comes with a little celebration.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text("You’ve given \(jar.store.formattedTotal)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsTint)
                .padding(.top, 10)

            CelebrationPicker()
                .padding(.top, 18)

            Button {
                withAnimation(.snappy) { jar.showsThanks = false }
            } label: {
                Text("You’re Welcome")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.dsTintFill)
            .padding(.top, 20)
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(Color(uiColor: .systemGroupedBackground), in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            heartBeat += 1
            jar.celebrate()
        }
    }
}

/// A compact capsule for tip amounts, so four fit across.
struct TipChipStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.dsTint)
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.horizontal, 6)
            .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
            .overlay { Capsule().strokeBorder(Color.dsTint, lineWidth: selected ? 1.5 : 0) }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
