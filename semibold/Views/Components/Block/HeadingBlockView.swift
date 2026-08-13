import SwiftUI

/// A heading block (§7.1/§7.3's `# `/`## `/`### ` conversions) — its
/// typography scales with `content.headingLevel`; no leading-column
/// marker.
struct HeadingBlockView: View {
    let item: DocumentItem
    let content: TextContent
    var focusedBlockId: FocusState<String?>.Binding
    @Binding var cursorOffsetToApply: Int?
    let onTextChange: (String) -> Void
    let onEnter: (String, Int) -> Void
    let onBackspaceAtStart: (String) -> Void

    /// Heading levels 1-3 map to `AppTheme.Typography.heading1`/
    /// `.heading2`/`.title` — level 3 (and any other/missing level) falls
    /// back to `.title`, matching the pre-split `BlockRow.textStyle`.
    private var textStyle: TextStyleToken {
        switch content.headingLevel {
        case 1: return AppTheme.Typography.heading1
        case 2: return AppTheme.Typography.heading2
        default: return AppTheme.Typography.title
        }
    }

    var body: some View {
        BlockRowChrome(
            item: item,
            content: content,
            focusedBlockId: focusedBlockId,
            cursorOffsetToApply: $cursorOffsetToApply,
            textStyle: textStyle,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart
        )
    }
}
