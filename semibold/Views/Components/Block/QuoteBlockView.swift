import SwiftUI

/// A blockquote block (§7.1/§7.3's `> quote` syntax) — a vertical rule
/// in the leading column, and dimmed (`AppTheme.Colors.Content
/// .secondary`) text so it reads as a quote, distinct from surrounding
/// paragraph text.
struct QuoteBlockView: View {
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
            textColor: AppTheme.Colors.Content.secondary,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart
        ) {
            Rectangle()
                .fill(AppTheme.Colors.Stroke.border)
                .frame(width: AppTheme.Spacing.xs)
                .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
        }
    }
}
