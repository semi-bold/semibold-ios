import SwiftUI

/// A checklist block (§7.1's `- [ ] item` syntax) — a tappable checkbox
/// in the leading column that toggles the task's done/not-done state.
///
/// A plain `enum` with a static factory rather than a `View` struct — see
/// `BlockRowChrome`'s doc comment for why: every per-kind block returns
/// `BlockRowChrome` directly so `DetailScreen.blockRow(for:content:)`'s
/// switch produces one uniform concrete type across all `content.textKind`
/// cases.
enum ChecklistBlockView {
    static func chrome(
        item: DocumentItem,
        content: TextContent,
        /// This item's nesting depth (0 for top-level) — see
        /// `DetailViewModel.depth(forItemId:)`. Forwarded straight to
        /// `BlockRowChrome`, which renders the per-level indent.
        depth: Int,
        focusedBlockId: FocusState<String?>.Binding,
        cursorOffsetToApply: Binding<Int?>,
        onTextChange: @escaping (String) -> Void,
        onEnter: @escaping (String, Int) -> Void,
        onBackspaceAtStart: @escaping (String) -> Void,
        onToggleChecklist: @escaping () -> Void
    ) -> BlockRowChrome {
        BlockRowChrome(
            item: item,
            content: content,
            focusedBlockId: focusedBlockId,
            cursorOffsetToApply: cursorOffsetToApply,
            textStyle: AppTheme.Typography.body,
            leadingContent: .checkbox(isChecked: content.isChecked ?? false, action: onToggleChecklist),
            depth: depth,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart
        )
    }
}
