import Foundation

/// macOS keyboard-shortcut actions (`tasks/NO-001.md` §13.2) applied to the
/// currently-focused block in the editor:
///
/// - Cmd+Option+1/2/3 → convert the focused block to Heading 1/2/3.
/// - Cmd+B / Cmd+I    → toggle a `**bold**`/`*italic*` Markdown wrapper
///   around the focused block's whole text.
/// - Cmd+K            → wrap the focused block's whole text as a
///   `[text](url)` Markdown link (or unwrap it back to plain text).
///
/// **Scoping deviation from §13.2**: §13.2 describes these as acting on
/// the current text *selection*. `ParagraphTextField` (a thin
/// `UITextView` wrapper, `block-editor-phase3`) doesn't expose the
/// selection range to SwiftUI, so these act on the focused block's entire
/// text instead — toggling the Markdown delimiters around the whole block
/// rather than around a selected run. This mirrors how AC1-AC5's typed
/// Markdown prefixes already convert a whole block, and keeps the
/// shortcuts usable without a larger editor rework. Selection-scoped
/// formatting is a natural follow-up once `ParagraphTextField` exposes
/// `UITextView.selectedRange`.
///
/// **NO-005 note**: like `updateBlockText`, this wraps/unwraps the
/// delimiters directly in `TextContent.plainText` rather than recording a
/// `TextMark` — see `DetailViewModel.marksByItemId`'s doc comment for why.
///
/// Split out of `DetailViewModel.swift` following the
/// `+MarkdownConversion` extension-file precedent — keeps the
/// create/edit/split/merge/reorder logic in one file and all
/// keyboard-shortcut-driven formatting in this one.
extension DetailViewModel {
    /// Converts the block identified by `blockId` to a heading at `level`
    /// (1-3), keeping its current text (Cmd+Option+1/2/3, §13.2).
    ///
    /// Applies to any block type — a paragraph, list item, etc. all become
    /// a heading at `level` holding their current display text. Does
    /// nothing if `blockId` doesn't exist. This is a structural change, so
    /// it's persisted immediately (PLANNING §11.2 "블록 생성/삭제/순서 변경:
    /// 즉시 저장"), like AC1's typed `# `/`## `/`### ` conversion.
    func convertBlockToHeading(_ blockId: String, level: Int) {
        guard items.contains(where: { $0.id == blockId }) else { return }
        let text = textContent(forItemId: blockId).plainText

        textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.heading, plainText: text, headingLevel: level)

        cancelPendingSave(blockId)
        persistBlock(blockId)
    }

    /// Toggles a `**bold**` wrapper around the focused block's whole text
    /// (Cmd+B, §13.2). If the text is already fully wrapped in `**…**`,
    /// removes the wrapper instead — so the shortcut acts as an on/off
    /// toggle. Does nothing for empty text (nothing to wrap).
    func toggleBoldOnBlock(_ blockId: String) {
        toggleDelimiter("**", onBlock: blockId)
    }

    /// Toggles a `*italic*` wrapper around the focused block's whole text
    /// (Cmd+I, §13.2). Tries `**bold**` first when checking whether the
    /// text is already wrapped, so a bold block's `**text**` isn't
    /// misread as italic-wrapped `*...*` (which would strip only the
    /// outer `*` of each `**`). Does nothing for empty text.
    func toggleItalicOnBlock(_ blockId: String) {
        toggleDelimiter("*", onBlock: blockId)
    }

    /// Wraps the focused block's whole text as a `[text](url)` Markdown
    /// link (Cmd+K, §13.2), with an empty `url` placeholder for the user to
    /// fill in. If the text is already a whole-text link (`[text](url)`),
    /// unwraps it back to plain `text` instead — a toggle, like
    /// `toggleBoldOnBlock`/`toggleItalicOnBlock`. Does nothing for empty
    /// text.
    func toggleLinkOnBlock(_ blockId: String) {
        let text = textContent(forItemId: blockId).plainText
        guard !text.isEmpty else { return }

        let newText: String
        if let unwrapped = Self.unwrapLink(text) {
            newText = unwrapped
        } else {
            newText = "[\(text)]()"
        }

        applyPlainTextEdit(newText, toBlock: blockId)
    }

    /// Wraps (or unwraps) `delimiter` around `blockId`'s whole text, shared
    /// by `toggleBoldOnBlock`/`toggleItalicOnBlock`.
    private func toggleDelimiter(_ delimiter: String, onBlock blockId: String) {
        let text = textContent(forItemId: blockId).plainText
        guard !text.isEmpty else { return }

        let newText: String
        if let unwrapped = Self.unwrapDelimiter(delimiter, from: text) {
            newText = unwrapped
        } else {
            newText = delimiter + text + delimiter
        }

        applyPlainTextEdit(newText, toBlock: blockId)
    }

    /// Returns `text` with a leading/trailing `delimiter` pair removed, or
    /// `nil` if `text` isn't wholly wrapped in `delimiter` (or removing it
    /// would leave nothing — an empty inner string doesn't round-trip back
    /// to a meaningful wrap).
    ///
    /// For `delimiter == "*"` (italic), a `"**bold**"`-wrapped text starts
    /// and ends with `*` too, but stripping a single `*` from each end
    /// would leave `"*bold*"` — a mismatched partial unwrap of the bold
    /// delimiters, not a real italic toggle-off. So `"*"` only unwraps text
    /// that isn't ALSO `"**"`-wrapped (i.e. genuinely single-`*`-wrapped),
    /// leaving a `**bold**` block's Cmd+I to wrap it again as
    /// `"***bold***"` instead.
    private static func unwrapDelimiter(_ delimiter: String, from text: String) -> String? {
        guard text.hasPrefix(delimiter), text.hasSuffix(delimiter) else { return nil }
        if delimiter == "*", text.hasPrefix("**"), text.hasSuffix("**") { return nil }

        let inner = text.dropFirst(delimiter.count).dropLast(delimiter.count)
        guard !inner.isEmpty else { return nil }
        return String(inner)
    }

    /// Returns the inner `text` of a whole-text `[text](url)` Markdown
    /// link, or `nil` if `text` isn't wholly a single link span.
    private static func unwrapLink(_ text: String) -> String? {
        guard text.hasPrefix("["), text.hasSuffix(")") else { return nil }
        guard let closeBracket = text.firstIndex(of: "]") else { return nil }
        let afterBracket = text.index(after: closeBracket)
        guard afterBracket < text.endIndex, text[afterBracket] == "(" else { return nil }

        let linkText = text[text.index(after: text.startIndex)..<closeBracket]
        guard !linkText.isEmpty else { return nil }
        return String(linkText)
    }

    /// Applies a plain-text edit (`updateBlockText`'s non-debounced
    /// conversions follow this same shape) to `blockId` and persists it
    /// immediately — keyboard-shortcut formatting is a deliberate
    /// structural edit, not a keystroke to debounce.
    private func applyPlainTextEdit(_ text: String, toBlock blockId: String) {
        guard items.contains(where: { $0.id == blockId }) else { return }
        let currentKind = textContent(forItemId: blockId).textKind

        switch currentKind {
        case TextItemKind.heading:
            let level = textContent(forItemId: blockId).headingLevel
            textContents[blockId] = TextContent(itemId: blockId, textKind: currentKind, plainText: text, headingLevel: level)
        case TextItemKind.checklist:
            let checked = textContent(forItemId: blockId).isChecked ?? false
            textContents[blockId] = TextContent(itemId: blockId, textKind: currentKind, plainText: text, isChecked: checked)
        default:
            textContents[blockId] = TextContent(itemId: blockId, textKind: currentKind, plainText: text)
        }

        cancelPendingSave(blockId)
        persistBlock(blockId)
    }
}
