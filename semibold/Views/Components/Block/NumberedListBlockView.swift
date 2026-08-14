import SwiftUI

/// A numbered-list-item block (§7.1/§7.3's `1. item` syntax) — this
/// item's position among consecutive numbered-list siblings
/// (`numberedListNumber`, from `DetailViewModel
/// .numberedListNumber(forItemId:)`), followed by a period, in the
/// leading column before the item's text.
///
/// A plain `enum` with a static factory rather than a `View` struct — see
/// `BlockRowChrome`'s doc comment for why: every per-kind block returns
/// `BlockRowChrome` directly so `DetailScreen.blockRow(for:content:)`'s
/// switch produces one uniform concrete type across all `content.textKind`
/// cases.
enum NumberedListBlockView {
    static func chrome(
        item: DocumentItem,
        content: TextContent,
        /// This row's position among consecutive numbered-list-item
        /// siblings — see `DetailViewModel.numberedListNumber(forItemId:)`.
        numberedListNumber: Int,
        /// This item's nesting depth (0 for top-level) — see
        /// `DetailViewModel.depth(forItemId:)`. Forwarded straight to
        /// `BlockRowChrome`, which renders the per-level indent.
        depth: Int,
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
            leadingContent: .marker("\(numberedListNumber)."),
            depth: depth,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart
        )
    }
}
