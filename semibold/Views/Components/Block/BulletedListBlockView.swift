import SwiftUI

/// A bulleted-list-item block (§7.1/§7.3's `- item` syntax) — a `•`
/// marker in the leading column before the item's text.
struct BulletedListBlockView: View {
    let item: DocumentItem
    let content: TextContent
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
            Text("•")
                .appTextStyle(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.Content.primary)
                .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
        }
    }
}
