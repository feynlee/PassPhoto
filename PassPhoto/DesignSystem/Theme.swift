import SwiftUI
import UIKit

/// PassPhoto color tokens (from the design system). Apple system colors cover backgrounds, labels and
/// separators; these are the tint, the check states and the guide colors drawn over photos.
extension Color {
    /// The one accent, the navy of a US passport cover: links, icons, outlines and passed checks. Navy is
    /// unreadable on black, so dark mode uses a brighter blue of the same hue (225°) that still reads.
    static let dsTint = Color(light: 0x1F2D5A, dark: 0x7A92DA)
    /// Filled buttons: the icon's navy exactly, in both themes, with white text.
    static let dsTintFill = Color(rgb: 0x1F2D5A)
    /// Text and symbols on a `dsTint` fill.
    static let dsOnTint = Color(light: 0xFFFFFF, dark: 0x0E1633)
    /// Selected rows and status capsules for passed checks.
    static let dsTintSoft = Color(light: 0xE4E9F5, dark: 0x1B2547)
    /// A check that needs a look. Always paired with an exclamation symbol.
    static let dsAttention = Color(light: 0xB25000, dark: 0xFF9F0A)
    static let dsAttentionSoft = Color(light: 0xFCEBDC, dark: 0x3D2605)
    /// A check that fails the requirement. Always paired with an xmark symbol.
    static let dsFail = Color(light: 0xC4281C, dark: 0xFF6961)
    static let dsFailSoft = Color(light: 0xFBE3E1, dark: 0x3F1715)

    /// Guides drawn over the photo. They don't change with the theme: they sit on the photo and its dimmed
    /// surround, always with a dark halo.
    static let dsGuidePass = Color(rgb: 0xA9BCF0)
    static let dsGuideAttention = Color(rgb: 0xFFB340)
    static let dsGuideNeutral = Color.white
    /// The photo outside the crop frame.
    static let dsMask = Color.black.opacity(0.55)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(rgb: UInt32) {
        self.init(uiColor: UIColor(rgb: rgb))
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Font {
    /// Measurements ("34.2 mm"): monospaced digits so values don't jitter while panning.
    static let dsMeasure = Font.system(.footnote, design: .default).monospacedDigit().weight(.medium)
}

extension CheckStatus {
    var color: Color {
        switch self {
        case .pass: .dsTint
        case .attention: .dsAttention
        case .fail: .dsFail
        case .pending: .secondary
        }
    }

    var softColor: Color {
        switch self {
        case .pass: .dsTintSoft
        case .attention: .dsAttentionSoft
        case .fail: .dsFailSoft
        case .pending: Color(uiColor: .tertiarySystemFill)
        }
    }

    var symbol: String {
        switch self {
        case .pass: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        case .pending: "circle.dotted"
        }
    }

    var guideColor: Color {
        switch self {
        case .pass: .dsGuidePass
        case .attention, .fail: .dsGuideAttention
        case .pending: .dsGuideNeutral
        }
    }
}

/// PassPhoto's buttons, in the icon's navy: `prominent` is solid navy with white text; otherwise a navy
/// outline with navy text on the surface, in place of iOS's pale tinted fill.
struct BrandButtonStyle: ButtonStyle {
    var prominent = false
    var height: CGFloat = 50

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(prominent ? Color.white : Color.dsTint)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 12)
            .background {
                if prominent {
                    Capsule().fill(Color.dsTintFill)
                } else {
                    Capsule().fill(Color(uiColor: .secondarySystemGroupedBackground))
                    Capsule().strokeBorder(Color.dsTint, lineWidth: 1.5)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var brand: BrandButtonStyle { BrandButtonStyle(prominent: true) }
    static var brandOutline: BrandButtonStyle { BrandButtonStyle() }
    static func brandOutline(height: CGFloat) -> BrandButtonStyle { BrandButtonStyle(height: height) }
}
