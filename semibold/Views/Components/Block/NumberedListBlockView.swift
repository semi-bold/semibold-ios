import SwiftUI

/// A numbered-list-item block (§7.1/§7.3's `1. item` syntax) — this
/// item's position among consecutive numbered-list siblings
/// (`numberedListNumber`, from `DetailViewModel
/// .numberedListNumber(forItemId:)`), followed by a period, in the
/// leading column before the item's text.
struct NumberedListBlockView: View {
    let item: DocumentItem
    let content: TextContent
    /// This row's position among consecutive numbered-list-item siblings
    /// — see `DetailViewModel.numberedListNumber(forItemId:)`.
    let numberedListNumber: Int
    var focusedBlockId: FocusState<String?>.Binding
    @Binding var cursorOffsetToApply: Int?
    let onTextChange: (String) -> Void
    let onEnter: (String, Int) -> Void
    let onBackspaceAtStart: (String) -> Void

    var body: some View {
        BlockRowChrome(
            item: item,
            content: content,
            focusedBlockId: focusedBlockId,
            cursorOffsetToApply: $cursorOffsetToApply,
            textStyle: AppTheme.Typography.body,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart
        ) {
            Text("\(numberedListNumber).")
                .appTextStyle(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.Content.primary)
                .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
        }
    }
}
