import Foundation

/// Inline Markdown mark parsing (`markdown-phase4` AC6): turns a block's
/// plain typed text into `[RichTextSpan]`, detecting `**bold**`,
/// `*italic*`, `~~strike~~`, `` `inline code` ``, and `[text](url)` (§7.1/
/// §7.3) so `contentJSON.text` carries the right `marks`/`href` for each
/// run of text.
///
/// Split into its own file following AC4's extension-file convention
/// (`DetailViewModel+MarkdownConversion.swift`) — this is the
/// `BlockContent`-side counterpart, used by `DetailViewModel` whenever a
/// block's text changes.
///
/// **Deviation from §8.1's literal `RichTextSpan.text`**: each span's
/// `text` keeps its Markdown delimiters (`"**bold**"`, not `"bold"`) rather
/// than stripping them. `DocumentBlock.displayText` is
/// `contentJSON.text.map(\.text).joined()` — the same text
/// `ParagraphTextField`'s `UITextView` shows and edits — so if parsing
/// stripped delimiters, `displayText` would silently rewrite what the user
/// typed (turning `"**bold**"` into `"bold"`) on every keystroke, fighting
/// the editor's `onChange(of: block.contentJSON)` sync and effectively
/// making `**`/`*`/etc. impossible to type. Keeping delimiters in `text`
/// means `marks`/`href` correctly describe *which* run of (still-literal)
/// text is bold/italic/etc. for `contentJSON`/AC7, without disturbing the
/// edit loop. A future `quality-phase5` "WYSIWYG" pass that renders
/// `NSAttributedString` (hiding delimiters visually) would be the natural
/// place to revisit this and strip delimiters from `text` once `displayText`
/// no longer needs to be delimiter-literal.
extension RichTextSpan {
    /// One inline Markdown syntax this parser recognizes, in the order
    /// they're tried at each position. Order matters where syntax overlaps:
    /// `**bold**` must be tried before `*italic*` so `**word**` isn't first
    /// read as `*` (italic) + literal `*word*` + `*`.
    private struct InlineSyntax {
        /// The literal delimiter that opens and closes this span, e.g.
        /// `"**"` for bold.
        let delimiter: String
        /// The mark this syntax applies to the enclosed (delimiter-
        /// inclusive) text.
        let mark: RichTextMark
    }

    private static let delimiterSyntaxes: [InlineSyntax] = [
        InlineSyntax(delimiter: "**", mark: .bold),
        InlineSyntax(delimiter: "~~", mark: .strike),
        InlineSyntax(delimiter: "`", mark: .inlineCode),
        InlineSyntax(delimiter: "*", mark: .italic)
    ]

    /// Parses `markdownText` for inline Markdown syntax (§7.1/§7.3:
    /// `**bold**`, `*italic*`, `~~strike~~`, `` `inline code` ``,
    /// `[text](url)`), splitting it into `[RichTextSpan]` with the matching
    /// `marks`/`href` on each formatted run and plain `RichTextSpan`s for
    /// everything else. Each span's `text` keeps its literal Markdown
    /// characters (including delimiters) — see this file's doc comment.
    ///
    /// - An empty `markdownText` returns an empty array.
    /// - Unterminated syntax (e.g. `"**bold"` with no closing `**`) is left
    ///   as plain text, matching AC1-AC5's "must match the full pattern to
    ///   convert" precedent — a span isn't marked until both delimiters are
    ///   typed.
    /// - Adjacent marked spans (e.g. `"**a** **b**"`) each become their own
    ///   `RichTextSpan`; the plain space between them becomes its own
    ///   unstyled span.
    /// - This doesn't aim for full CommonMark compliance (e.g. nested marks
    ///   like `**bold *and italic***` aren't specially recognized — the
    ///   inner `*...*` is treated as literal text inside the bold span) —
    ///   §7.3's literal examples are the bar.
    static func parse(markdownText: String) -> [RichTextSpan] {
        guard !markdownText.isEmpty else { return [] }

        var spans: [RichTextSpan] = []
        var plainBuffer = ""
        var remainder = Substring(markdownText)

        func flushPlainBuffer() {
            if !plainBuffer.isEmpty {
                spans.append(RichTextSpan(text: plainBuffer))
                plainBuffer = ""
            }
        }

        while !remainder.isEmpty {
            if let link = matchLink(in: remainder) {
                flushPlainBuffer()
                spans.append(RichTextSpan(text: link.text, marks: [.link], href: link.href))
                remainder = remainder[link.endIndex...]
                continue
            }

            if let match = matchDelimitedSpan(in: remainder) {
                flushPlainBuffer()
                spans.append(RichTextSpan(text: match.text, marks: [match.mark]))
                remainder = remainder[match.endIndex...]
                continue
            }

            plainBuffer.append(remainder.removeFirst())
        }

        flushPlainBuffer()
        return spans
    }

    /// A successful inline-syntax match starting at the beginning of the
    /// scanned substring.
    private struct InlineMatch {
        /// The matched text, including its delimiters (e.g. `"**bold**"`).
        let text: String
        /// The mark to apply to `text`.
        let mark: RichTextMark
        /// The index in the original substring right after the closing
        /// delimiter, i.e. where scanning should resume.
        let endIndex: Substring.Index
    }

    /// A successful `[text](url)` link match starting at the beginning of
    /// the scanned substring.
    private struct LinkMatch {
        /// The matched text, including its `[]()` syntax (e.g.
        /// `"[label](https://example.com)"`).
        let text: String
        let href: String
        let endIndex: Substring.Index
    }

    /// Tries each of `delimiterSyntaxes` (in order) against the start of
    /// `text`, returning the first that has both an opening and a matching
    /// closing delimiter with non-empty content between them. Returns `nil`
    /// if `text` doesn't start with any recognized delimiter, or if a
    /// delimiter it starts with has no closing match (unterminated syntax).
    private static func matchDelimitedSpan(in text: Substring) -> InlineMatch? {
        for syntax in delimiterSyntaxes {
            guard text.hasPrefix(syntax.delimiter) else { continue }

            let afterOpen = text.index(text.startIndex, offsetBy: syntax.delimiter.count)
            guard let closeRange = text.range(of: syntax.delimiter, range: afterOpen..<text.endIndex) else {
                // Unterminated — leave this delimiter character as plain
                // text rather than misparsing.
                continue
            }

            let inner = text[afterOpen..<closeRange.lowerBound]
            guard !inner.isEmpty else { continue }

            let fullMatch = text[text.startIndex..<closeRange.upperBound]
            return InlineMatch(text: String(fullMatch), mark: syntax.mark, endIndex: closeRange.upperBound)
        }
        return nil
    }

    /// Matches `[text](url)` (§7.1/§7.3's link syntax) at the start of
    /// `text`. Returns `nil` if `text` doesn't start with `[`, the link text
    /// is empty, there's no `](`, or the closing `)`/`href` is missing —
    /// unterminated/malformed link syntax stays plain text.
    private static func matchLink(in text: Substring) -> LinkMatch? {
        guard text.hasPrefix("[") else { return nil }

        let afterOpenBracket = text.index(after: text.startIndex)
        guard let closeBracketRange = text.range(of: "]", range: afterOpenBracket..<text.endIndex) else {
            return nil
        }

        let linkText = text[afterOpenBracket..<closeBracketRange.lowerBound]
        guard !linkText.isEmpty else { return nil }

        // `](` must immediately follow the closing `]`.
        guard closeBracketRange.upperBound < text.endIndex, text[closeBracketRange.upperBound] == "(" else {
            return nil
        }

        let afterOpenParen = text.index(after: closeBracketRange.upperBound)
        guard let closeParenRange = text.range(of: ")", range: afterOpenParen..<text.endIndex) else {
            return nil
        }

        let href = text[afterOpenParen..<closeParenRange.lowerBound]
        guard !href.isEmpty else { return nil }

        let fullMatch = text[text.startIndex..<closeParenRange.upperBound]
        return LinkMatch(text: String(fullMatch), href: String(href), endIndex: closeParenRange.upperBound)
    }
}
