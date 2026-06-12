import SwiftUI

/// Central design-token catalog for semi:bold, ported from
/// `sketch-autokit/sketch/tokens.py`.
///
/// Screens and components must read colors, spacing, typography, and
/// corner radii from here rather than hardcoding hex values, point
/// sizes, or magic numbers — this keeps the app in sync with the
/// wireframe/planning-spec source of truth.
enum AppTheme {
    /// Color palette. Mirrors `tokens.py` §1-5 (the dark-mode palette,
    /// which is the active/uncommented one in that file).
    enum Colors {
        // 1. Brand colors — primary actions, links, CTAs, status accents.
        static let primary = Color(hex: "#007AFF")
        static let secondary = Color(hex: "#34C759")
        static let danger = Color(hex: "#FF3B30")
        static let warning = Color(hex: "#FF9500")

        // 2. Background layers — darkest to lightest surface.
        static let background = Color(hex: "#111111")
        static let surface = Color(hex: "#1C1C1E")
        static let surface2 = Color(hex: "#2C2C2E")
        static let surface3 = Color(hex: "#3A3A3C")

        // 3. Text — primary, secondary/placeholder, label/caption.
        static let text1 = Color(hex: "#FFFFFF")
        static let text2 = Color(hex: "#8E8E93")
        static let text3 = Color(hex: "#636366")

        // 4. Separators / borders.
        static let divider = Color(hex: "#3A3A3C")
        static let border = Color(hex: "#48484A")

        // 5. Status colors.
        static let success = Color(hex: "#30D158")
        static let info = Color(hex: "#64D2FF")
        static let error = Color(hex: "#FF453A")
    }

    /// Spacing scale (8pt grid, 4px adjustments allowed). Mirrors
    /// `tokens.py` §7.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
        static let xxxl: CGFloat = 48
    }

    /// Corner radius scale. Mirrors `tokens.py` §9.
    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let full: CGFloat = 999
    }

    /// Typography scale — each style carries the font and its target
    /// line height, since SwiftUI fonts don't expose line-height
    /// directly. Mirrors `tokens.py` §8 (size, weight, line-height).
    enum Typography {
        static let heading1 = TextStyleToken(size: 28, weight: .bold, lineHeight: 36)
        static let heading2 = TextStyleToken(size: 24, weight: .bold, lineHeight: 32)
        static let title = TextStyleToken(size: 20, weight: .semibold, lineHeight: 28)
        static let body = TextStyleToken(size: 16, weight: .regular, lineHeight: 24)
        static let caption = TextStyleToken(size: 13, weight: .regular, lineHeight: 18)
        static let button = TextStyleToken(size: 16, weight: .semibold, lineHeight: 20)
        static let label = TextStyleToken(size: 13, weight: .semibold, lineHeight: 18)
    }
}

/// A single typography token: font size, weight, and the line height
/// the design expects for that style.
struct TextStyleToken {
    let size: CGFloat
    let weight: Font.Weight
    let lineHeight: CGFloat

    /// The SwiftUI font for this style.
    var font: Font {
        .system(size: size, weight: weight)
    }
}

extension View {
    /// Applies a typography token's font and the line spacing needed to
    /// reach its target line height, so screens can opt into the full
    /// `TextStyleToken` (not just its font) with one modifier.
    func appTextStyle(_ token: TextStyleToken) -> some View {
        font(token.font)
            .lineSpacing(token.lineHeight - token.size)
    }
}

private extension Color {
    /// Creates a `Color` from a `"#RRGGBB"` (or `"#AARRGGBB"`) hex string,
    /// matching the literal hex values declared in `tokens.py`.
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
