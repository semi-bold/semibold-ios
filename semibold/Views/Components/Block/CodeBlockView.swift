import SwiftUI

/// A code block (§7.1/§7.3's ` ```lang ` syntax) — monospaced text on a
/// distinguishing surface background (`n700` instead of the usual
/// `n900`), so code reads distinctly from prose. No leading-column
/// marker.
///
/// A code block's fence language identifier (e.g. `swift` for
/// ` ```swift `) isn't modeled on `TextContent` — see
/// `DetailViewModel.updateBlockText`'s doc comment — so no language
/// caption shows above the code here.
///
/// A plain `enum` with a static factory rather than a `View` struct — see
/// `BlockRowChrome`'s doc comment for why: every per-kind block returns
/// `BlockRowChrome` directly so `DetailScreen.blockRow(for:content:)`'s
/// switch produces one uniform concrete type across all `content.textKind`
/// cases.
enum CodeBlockView {
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
            isMonospaced: true,
            isCodeBlock: true,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart,
            onDismissKeyboard: onDismissKeyboard
        )
    }
}
