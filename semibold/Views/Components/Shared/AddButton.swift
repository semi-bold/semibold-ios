import SwiftUI

/// The "+" entry point for the new-folder/new-document menu
/// (`Planning_2_FolderCreateFlow`/`Planning_3_DocumentCreateFlow`/
/// `Planning_6_FolderNavigationFlow`'s single "+" callout), shared by
/// `HomeScreen` and `FolderContentsScreen` so both apply the same visual rule
/// instead of diverging.
///
/// Two placements share the same "+" glyph but read very differently per
/// `Planning_Nav_1_TopBarFlow` (FLOW-NAV-001):
/// - `.navBar` matches Figma's `PlusBtn`/`PlusBtn_Active` naming
///   literally: a plain "+" normally, with the light accent-tinted
///   circular background (`PlusBtn_Active`) appearing only while the
///   button is actively pressed.
/// - `.floating` matches Figma's `FAB_AddMenu`: a permanently
///   accent-filled circle with a white "+" and a drop shadow, anchored to
///   a screen's bottom-trailing corner once the NavBar's inline "+" moved
///   out to a floating button under this redesign.
struct AddButton: View {
    enum Placement {
        /// The inline NavBar "+" (`PlusBtn`/`PlusBtn_Active`).
        case navBar
        /// The floating bottom-trailing "+" (`FAB_AddMenu`).
        case floating
    }

    var placement: Placement = .navBar
    let action: () -> Void

    var body: some View {
        switch placement {
        case .navBar:
            Button(action: action) {
                plusGlyph(AppTheme.Typography.title)
            }
            .buttonStyle(AddButtonStyle())
        case .floating:
            Button(action: action) {
                plusGlyph(AppTheme.Typography.heading2)
            }
            .buttonStyle(FloatingAddButtonStyle())
        }
    }

    /// The "+" glyph both placements share — only its size (and each
    /// placement's own `ButtonStyle`) differs.
    private func plusGlyph(_ style: TextStyleToken) -> some View {
        Image(systemName: "plus")
            .appTextStyle(style)
    }
}

/// `.navBar` styling: a plain white "+" normally, with the light
/// accent-tinted circular background (`PlusBtn_Active`) appearing only
/// while the button is actively pressed — not permanently, which is what
/// `HomeScreen`'s previous hardcoded
/// `.background(AppTheme.Colors.accent.opacity(0.18), ...)` did
/// regardless of press state.
private struct AddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? AppTheme.Colors.accent : AppTheme.Colors.Content.primary)
            .frame(width: 40, height: 40)
            .background(
                configuration.isPressed ? AppTheme.Colors.accent.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.full)
            )
    }
}

/// `.floating` styling (`FAB_AddMenu`): a permanently accent-filled
/// circle with a white "+" and a drop shadow, so it reads as a floating
/// action button rather than an inline bar icon. Presses dim slightly
/// (rather than the `.navBar` style's tint-on-press) since the fill is
/// already accent-colored at rest.
private struct FloatingAddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.Colors.Content.primary)
            .frame(width: 56, height: 56)
            .background(AppTheme.Colors.accent, in: Circle())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    }
}
