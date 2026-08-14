import SwiftUI

/// A plain paragraph block — this document editor's default block kind
/// for freshly created blocks and any `content.textKind` this build
/// doesn't recognize (`DetailScreen.blockRow(for:content:)`'s fallback).
/// No leading-column marker; `.body` typography; primary text color.
///
/// A plain `enum` with a static factory rather than a `View` struct — see
/// `BlockRowChrome`'s doc comment for why: every per-kind block returns
/// `BlockRowChrome` directly so `DetailScreen.blockRow(for:content:)`'s
/// switch produces one uniform concrete type across all `content.textKind`
/// cases.
enum ParagraphBlockView {
    static func chrome(
        item: DocumentItem,
        content: TextContent,
        focusedBlockId: FocusState<String?>.Binding,
        cursorOffsetToApply: Binding<Int?>,
        onTextChange: @escaping (String) -> Void,
        onEnter: @escaping (String, Int) -> Void,
        onBackspaceAtStart: @escaping (String) -> Void,
        onDismissKeyboard: (() -> Void)? = nil
    ) -> BlockRowChrome {
        BlockRowChrome(
            item: item,
            content: content,
            focusedBlockId: focusedBlockId,
            cursorOffsetToApply: cursorOffsetToApply,
            textStyle: AppTheme.Typography.body,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart,
            onDismissKeyboard: onDismissKeyboard
        )
    }
}
