import SwiftUI

/// A bulleted-list-item block (§7.1/§7.3's `- item` syntax) — a `•`
/// marker in the leading column before the item's text.
///
/// A plain `enum` with a static factory rather than a `View` struct — see
/// `BlockRowChrome`'s doc comment for why: every per-kind block returns
/// `BlockRowChrome` directly so `DetailScreen.blockRow(for:content:)`'s
/// switch produces one uniform concrete type across all `content.textKind`
/// cases.
enum BulletedListBlockView {
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
        /// A hardware Tab press on this item — `DetailScreen.blockRow(for:
        /// content:)` supplies `{ viewModel.indentBlock(item.id) }` for
        /// this kind. `nil` (the default) leaves Tab's plain `UITextView`
        /// behavior unchanged (`tasks/NO-009.md` §2.1/§3.3).
        onIndent: (() -> Void)? = nil,
        /// A hardware Shift+Tab press on this item — see `onIndent`.
        onOutdent: (() -> Void)? = nil,
        /// Whether this item's on-screen toolbar outdent button is
        /// enabled — `DetailScreen.blockRow(for:content:)` supplies
        /// `item.parentItemId != nil` for this kind
        /// (`05-onscreen-keyboard-indent-toolbar` brief). Defaults to
        /// `true` so existing call sites don't need to change.
        canOutdent: Bool = true,
        /// A tap on the on-screen toolbar's keyboard-dismiss button — see
        /// `onIndent`.
        onDismissKeyboard: (() -> Void)? = nil
    ) -> BlockRowChrome {
        BlockRowChrome(
            item: item,
            content: content,
            focusedBlockId: focusedBlockId,
            cursorOffsetToApply: cursorOffsetToApply,
            textStyle: AppTheme.Typography.body,
            leadingContent: .marker("•"),
            depth: depth,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart,
            onIndent: onIndent,
            onOutdent: onOutdent,
            canOutdent: canOutdent,
            onDismissKeyboard: onDismissKeyboard
        )
    }
}
