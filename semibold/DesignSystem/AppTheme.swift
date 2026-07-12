import SwiftUI

/// Central design-token catalog for semi:bold, mirroring Figma Variables.
///
/// Screens and components must read colors, spacing, typography, and
/// corner radii from here rather than hardcoding values — this keeps
/// the app in sync with the Figma design source.
enum AppTheme {
    enum Colors {
        /// Interactive elements: tappable buttons, links, CTAs.
        static let accent = Color(hex: "#007AFF")

        /// Background layers — darkest (brand base) to lightest surface.
        enum Neutral {
            static let n900 = Color(hex: "#111111")
            static let n800 = Color(hex: "#1C1C1E")
            static let n700 = Color(hex: "#2C2C2E")
            static let n600 = Color(hex: "#3A3A3C")
        }

        /// Text hierarchy.
        enum Content {
            static let primary   = Color(hex: "#FFFFFF")
            static let secondary = Color(hex: "#8E8E93")
            static let tertiary  = Color(hex: "#636366")
        }

        /// Separators and borders.
        enum Stroke {
            static let divider = Color(hex: "#3A3A3C")
            static let border  = Color(hex: "#48484A")
        }

        /// Semantic status colors.
        enum Feedback {
            static let success = Color(hex: "#30D158")
            static let info    = Color(hex: "#64D2FF")
            static let error   = Color(hex: "#FF453A")
            static let warning = Color(hex: "#FF9500")
            static let danger  = Color(hex: "#FF3B30")
        }
    }

    /// Spacing scale (8pt grid, 4px adjustments allowed).
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
        static let xxxl: CGFloat = 48
    }

    /// Corner radius scale.
    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let full: CGFloat = 999
    }

    /// Typography scale — each style carries the font and its target
    /// line height, since SwiftUI fonts don't expose line-height directly.
    enum Typography {
        static let heading1 = TextStyleToken(size: 28, weight: .bold,     lineHeight: 36)
        static let heading2 = TextStyleToken(size: 24, weight: .bold,     lineHeight: 32)
        static let title    = TextStyleToken(size: 20, weight: .semibold, lineHeight: 28)
        static let body     = TextStyleToken(size: 16, weight: .regular,  lineHeight: 24)
        static let caption  = TextStyleToken(size: 13, weight: .regular,  lineHeight: 18)
        static let button   = TextStyleToken(size: 16, weight: .semibold, lineHeight: 20)
        static let label    = TextStyleToken(size: 13, weight: .semibold, lineHeight: 18)
    }
}

/// A single typography token: font size, weight, and the line height
/// the design expects for that style.
struct TextStyleToken {
    let size: CGFloat
    let weight: Font.Weight
    let lineHeight: CGFloat

    var font: Font {
        .system(size: size, weight: weight)
    }
}

extension View {
    /// Applies a typography token's font and the line spacing needed to
    /// reach its target line height.
    func appTextStyle(_ token: TextStyleToken) -> some View {
        font(token.font)
            .lineSpacing(token.lineHeight - token.size)
    }
}

private extension Color {
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")

        var rgba: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgba)

        let alpha, red, green, blue: UInt64
        switch hexString.count {
        case 8:
            (alpha, red, green, blue) = ((rgba >> 24) & 0xFF, (rgba >> 16) & 0xFF, (rgba >> 8) & 0xFF, rgba & 0xFF)
        case 6:
            (alpha, red, green, blue) = (0xFF, (rgba >> 16) & 0xFF, (rgba >> 8) & 0xFF, rgba & 0xFF)
        default:
            (alpha, red, green, blue) = (0xFF, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}
