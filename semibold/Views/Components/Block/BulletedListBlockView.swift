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
            leadingContent: .marker("•"),
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart
        )
    }
}
