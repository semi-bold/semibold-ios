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
struct CodeBlockView: View {
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
            isMonospaced: true,
            isCodeBlock: true,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart
        )
    }
}
