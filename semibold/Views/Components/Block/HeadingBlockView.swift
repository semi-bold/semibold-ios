import SwiftUI

/// A heading block (§7.1/§7.3's `# `/`## `/`### ` conversions) — its
/// typography scales with `content.headingLevel`; no leading-column
/// marker.
///
/// A plain `enum` with a static factory rather than a `View` struct — see
/// `BlockRowChrome`'s doc comment for why: every per-kind block returns
/// `BlockRowChrome` directly so `DetailScreen.blockRow(for:content:)`'s
/// switch produces one uniform concrete type across all `content.textKind`
/// cases.
enum HeadingBlockView {
    /// Heading levels 1-3 map to `AppTheme.Typography.heading1`/
    /// `.heading2`/`.title` — level 3 (and any other/missing level) falls
    /// back to `.title`, matching the pre-split `BlockRow.textStyle`.
    private static func textStyle(for content: TextContent) -> TextStyleToken {
        switch content.headingLevel {
        case 1: return AppTheme.Typography.heading1
        case 2: return AppTheme.Typography.heading2
        default: return AppTheme.Typography.title
        }
    }

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
            textStyle: textStyle(for: content),
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart
        )
    }
}
