import SwiftUI

/// The "+" entry point for the new-folder/new-document menu
/// (`Planning_2_FolderCreateFlow`/`Planning_3_DocumentCreateFlow`/
/// `Planning_6_FolderNavigationFlow`'s single "+" callout), shared by
/// `HomeView` and `FolderContentsView` so both apply the same visual rule
/// instead of diverging.
///
/// Matches Figma's `PlusBtn`/`PlusBtn_Active` naming literally: a plain
/// white "+" normally, with the light accent-tinted circular background
/// (`PlusBtn_Active`) appearing only while the button is actively
/// pressed — not permanently, which is what `HomeView`'s previous
/// hardcoded `.background(AppTheme.Colors.accent.opacity(0.18), ...)` did
/// regardless of press state.
struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .appTextStyle(AppTheme.Typography.title)
        }
        .buttonStyle(AddButtonStyle())
    }
}

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
