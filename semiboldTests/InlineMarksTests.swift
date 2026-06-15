import Testing

@testable import semibold

/// Tests for `RichTextSpan.parse(markdownText:)` (`markdown-phase4` AC6) —
/// splitting a block's typed text into `[RichTextSpan]` with `marks`/`href`
/// for `**bold**`, `*italic*`, `~~strike~~`, `` `inline code` ``, and
/// `[text](url)` (§7.1/§7.3).
///
/// Per `BlockContent+InlineMarks.swift`'s documented deviation, each span's
/// `text` keeps its Markdown delimiters (e.g. `"**bold**"`, not `"bold"`) so
/// `DocumentBlock.displayText` (the joined spans) stays equal to the
/// literally-typed text the editor shows/edits.
struct InlineMarksTests {
    @Test("Plain text with no Markdown syntax stays a single unmarked span")
    func plainTextStaysUnmarked() throws {
        let spans = RichTextSpan.parse(markdownText: "Just plain text")
        #expect(spans == [RichTextSpan(text: "Just plain text")])
    }

    @Test("Empty text parses to no spans")
    func emptyTextParsesToNoSpans() throws {
        #expect(RichTextSpan.parse(markdownText: "") == [])
    }

    @Test("**bold** becomes a single bold-marked span")
    func boldSyntax() throws {
        let spans = RichTextSpan.parse(markdownText: "**bold**")
        #expect(spans == [RichTextSpan(text: "**bold**", marks: [.bold])])
    }

    @Test("*italic* becomes a single italic-marked span")
    func italicSyntax() throws {
        let spans = RichTextSpan.parse(markdownText: "*italic*")
        #expect(spans == [RichTextSpan(text: "*italic*", marks: [.italic])])
    }

    @Test("~~strike~~ becomes a single strike-marked span")
    func strikeSyntax() throws {
        let spans = RichTextSpan.parse(markdownText: "~~strike~~")
        #expect(spans == [RichTextSpan(text: "~~strike~~", marks: [.strike])])
    }

    @Test("`code` becomes a single inline-code-marked span")
    func inlineCodeSyntax() throws {
        let spans = RichTextSpan.parse(markdownText: "`code`")
        #expect(spans == [RichTextSpan(text: "`code`", marks: [.inlineCode])])
    }

    @Test("[text](url) becomes a single link-marked span with href")
    func linkSyntax() throws {
        let spans = RichTextSpan.parse(markdownText: "[example](https://example.com)")
        #expect(spans == [
            RichTextSpan(text: "[example](https://example.com)", marks: [.link], href: "https://example.com")
        ])
    }

    @Test("'plain **bold** plain' splits into plain/bold/plain spans")
    func mixedBoldAndPlainText() throws {
        let spans = RichTextSpan.parse(markdownText: "plain **bold** plain")
        #expect(spans == [
            RichTextSpan(text: "plain "),
            RichTextSpan(text: "**bold**", marks: [.bold]),
            RichTextSpan(text: " plain")
        ])
    }

    @Test("'**bold** text' splits into bold span and trailing plain span")
    func boldThenPlainText() throws {
        let spans = RichTextSpan.parse(markdownText: "**bold** text")
        #expect(spans == [
            RichTextSpan(text: "**bold**", marks: [.bold]),
            RichTextSpan(text: " text")
        ])
    }

    @Test("Unterminated '**bold' (no closing **) stays a single plain span")
    func unterminatedBoldStaysPlain() throws {
        let spans = RichTextSpan.parse(markdownText: "**bold")
        #expect(spans == [RichTextSpan(text: "**bold")])
    }

    @Test("Unterminated '*italic' (no closing *) stays a single plain span")
    func unterminatedItalicStaysPlain() throws {
        let spans = RichTextSpan.parse(markdownText: "*italic")
        #expect(spans == [RichTextSpan(text: "*italic")])
    }

    @Test("Unterminated '`code' (no closing backtick) stays a single plain span")
    func unterminatedInlineCodeStaysPlain() throws {
        let spans = RichTextSpan.parse(markdownText: "`code")
        #expect(spans == [RichTextSpan(text: "`code")])
    }

    @Test("Unterminated '[label](url' (no closing paren) stays a single plain span")
    func unterminatedLinkStaysPlain() throws {
        let spans = RichTextSpan.parse(markdownText: "[label](url")
        #expect(spans == [RichTextSpan(text: "[label](url")])
    }

    @Test("Adjacent marked spans '**a** **b**' each become their own span")
    func adjacentMarkedSpans() throws {
        let spans = RichTextSpan.parse(markdownText: "**a** **b**")
        #expect(spans == [
            RichTextSpan(text: "**a**", marks: [.bold]),
            RichTextSpan(text: " "),
            RichTextSpan(text: "**b**", marks: [.bold])
        ])
    }

    @Test("'**bold** and *italic*' combines two different marks with plain text between")
    func boldAndItalicCombined() throws {
        let spans = RichTextSpan.parse(markdownText: "**bold** and *italic*")
        #expect(spans == [
            RichTextSpan(text: "**bold**", marks: [.bold]),
            RichTextSpan(text: " and "),
            RichTextSpan(text: "*italic*", marks: [.italic])
        ])
    }

    @Test("'**bold**' is not misread as italic — '**' is tried before '*'")
    func boldNotMisreadAsItalic() throws {
        let spans = RichTextSpan.parse(markdownText: "**bold** plain")
        #expect(spans.first == RichTextSpan(text: "**bold**", marks: [.bold]))
    }

    @Test("Empty delimiters '****'/'[]()' don't produce an empty marked span")
    func emptyDelimitedContentStaysPlain() throws {
        let boldEmpty = RichTextSpan.parse(markdownText: "****")
        #expect(boldEmpty == [RichTextSpan(text: "****")])

        let linkEmpty = RichTextSpan.parse(markdownText: "[]()")
        #expect(linkEmpty == [RichTextSpan(text: "[]()")])
    }
}
