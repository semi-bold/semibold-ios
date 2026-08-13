import SwiftUI

/// A divider block's row — a horizontal rule that's editable Markdown
/// (the Slash Command "Divider" option, §12.2) when focused, and shown
/// as a plain rule otherwise.
///
/// A plain `enum` with a static factory rather than a `View` struct — see
/// `BlockRowChrome`'s doc comment for why: every per-kind block returns
/// `BlockRowChrome` directly so `DetailScreen.blockRow(for:content:)`'s
/// switch produces one uniform concrete type across all `content.textKind`
/// cases. `isDividerRow: true` is the only thing this factory adds —
/// `BlockRowChrome` owns the render↔edit toggle mechanism itself (see its
/// `showsDividerRule`/`dividerRuleOverlay`), since that mechanism turned
/// out to be fragile enough (`tasks/NO-007.md` §0, commit `9aba150`:
/// tapping the rendered `---` rule used to fail to focus the field
/// underneath it) that it belongs with the one view that actually owns
/// the always-mounted text field, not duplicated per call site.
enum DividerBlockView {
    static func chrome(
        item: DocumentItem,
        content: TextContent,
        focusedBlockId: FocusState<String?>.Binding,
        cursorOffsetToApply: Binding<Int?>,
        onTextChange: @escaping (String) -> Void,
        onEnter: @escaping (String, Int) -> Void,
        onBackspaceAtStart: @escaping (String) -> Void
    ) -> BlockRowChrome {
        BlockRowChrome(
            item: item,
            content: content,
            focusedBlockId: focusedBlockId,
            cursorOffsetToApply: cursorOffsetToApply,
            textStyle: AppTheme.Typography.body,
            isDividerRow: true,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart
        )
    }
}
