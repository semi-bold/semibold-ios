import SwiftUI

/// A plain paragraph block — this document editor's default block kind
/// for freshly created blocks and any `content.textKind` this build
/// doesn't recognize (`DetailScreen.blockRow(for:content:)`'s fallback).
/// No leading-column marker; `.body` typography; primary text color.
struct ParagraphBlockView: View {
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
        )
    }
}
