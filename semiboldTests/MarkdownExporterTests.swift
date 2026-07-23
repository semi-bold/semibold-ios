import Foundation
import Testing

@testable import semibold

/// Tests for `MarkdownExporter.render` — §10.3's "Markdown Renderer" /
/// "`.md` 문자열 생성" step, given a `Document` and its already-ordered
/// `[DocumentItem]`s (each backed by a `TextContent` and, for migrated
/// content, `TextMark`s).
///
/// **NO-005 model note**: rewritten against `MarkdownExporter.render
/// (documentTitle:items:textContents:marksByItemId:)`, which replaced the
/// pre-NO-005 `render(documentTitle:blocks:)` taking `[DocumentBlock]`
/// (`tasks/NO-005.md` §8 Phase 5, AC6). Every block-type/joining-rule case
/// the old file covered (heading, paragraph, bulleted/numbered/checklist
/// lists, blockquote, code block, divider, all-types-in-order, empty list)
/// is preserved below, translated to `DocumentItem`/`TextContent` — plus
/// new cases exercising `marksByItemId` (`TextMarkdownReconstruction`),
/// which didn't exist in the old model at all, added because `MarkdownExporter`
/// had three real data-integrity bugs found and fixed during brief 04's
/// review rounds (`orderKey` ordering, mark-based formatting silently lost
/// on export, stale marks corrupting export after an edit) — the two
/// deliberate gaps this file's coverage otherwise wouldn't catch.
///
/// One case couldn't be translated 1:1: the old
/// `fallsBackToDisplayTextWhenMarkdownSourceIsNil` test exercised
/// `DocumentBlock.markdownSource == nil` falling back to `displayText` —
/// `TextContent` has no `markdownSource` field at all (`DOCUMENT_MODEL.md`
/// §4.1's `text_items` shape only has `plainText`), so there's no
/// "source is nil" state to fall back from anymore; `plainText` is always
/// what's rendered. Replaced with a same-spirit test
/// (`rendersPlainParagraphTextUnchangedWithNoMarks`) confirming a plain
/// paragraph with no recorded marks renders its `plainText` as-is.
struct MarkdownExporterTests {
    private func makeDocument() -> Document {
        Document(title: "Diary")
    }

    private func makeItem(orderKey: String, contentType: String = "text") -> DocumentItem {
        DocumentItem(documentId: "doc-1", contentType: contentType, orderKey: orderKey)
    }

    @Test("Renders a heading followed by a paragraph with a blank line between them")
    func rendersHeadingAndParagraphWithBlankLineBetween() {
        let document = makeDocument()
        let heading = makeItem(orderKey: "0")
        let paragraph = makeItem(orderKey: "1")
        let textContents = [
            heading.id: TextContent(itemId: heading.id, textKind: TextItemKind.heading, plainText: "Title", headingLevel: 1),
            paragraph.id: TextContent(itemId: paragraph.id, textKind: TextItemKind.paragraph, plainText: "Hello world"),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, items: [heading, paragraph], textContents: textContents)

        #expect(markdown == "# Title\n\nHello world")
    }

    @Test("Renders consecutive bulleted list items on adjacent lines, no blank line between them")
    func rendersConsecutiveBulletedListItemsWithoutBlankLines() {
        let document = makeDocument()
        let intro = makeItem(orderKey: "0")
        let milk = makeItem(orderKey: "1")
        let eggs = makeItem(orderKey: "2")
        let textContents = [
            intro.id: TextContent(itemId: intro.id, textKind: TextItemKind.paragraph, plainText: "Shopping list"),
            milk.id: TextContent(itemId: milk.id, textKind: TextItemKind.bulletedListItem, plainText: "Milk"),
            eggs.id: TextContent(itemId: eggs.id, textKind: TextItemKind.bulletedListItem, plainText: "Eggs"),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, items: [intro, milk, eggs], textContents: textContents)

        #expect(markdown == "Shopping list\n\n- Milk\n- Eggs")
    }

    @Test("Renders consecutive numbered list items without blank lines, but checklist items in a separate run")
    func rendersNumberedListThenChecklistWithBlankLineBetweenFamilies() {
        let document = makeDocument()
        let first = makeItem(orderKey: "0")
        let second = makeItem(orderKey: "1")
        let task = makeItem(orderKey: "2")
        let textContents = [
            first.id: TextContent(itemId: first.id, textKind: TextItemKind.numberedListItem, plainText: "First"),
            second.id: TextContent(itemId: second.id, textKind: TextItemKind.numberedListItem, plainText: "Second"),
            task.id: TextContent(itemId: task.id, textKind: TextItemKind.checklist, plainText: "Task", isChecked: false),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, items: [first, second, task], textContents: textContents)

        #expect(markdown == "1. First\n2. Second\n\n- [ ] Task")
    }

    @Test("Renders a blockquote and a code block surrounded by blank lines")
    func rendersBlockquoteAndCodeBlockWithBlankLines() {
        let document = makeDocument()
        let quote = makeItem(orderKey: "0")
        let code = makeItem(orderKey: "1")
        let textContents = [
            quote.id: TextContent(itemId: quote.id, textKind: TextItemKind.quote, plainText: "Wise words"),
            code.id: TextContent(itemId: code.id, textKind: TextItemKind.codeBlock, plainText: "let x = 1"),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, items: [quote, code], textContents: textContents)

        // NO-005 deviation: the code fence's language identifier
        // (`swift` in the pre-NO-005 version of this test) has nowhere to
        // live on `TextContent` (`MarkdownExporter.markdownLine`'s doc
        // comment) — code blocks always export as a plain, language-less
        // fence now.
        #expect(markdown == "> Wise words\n\n```\nlet x = 1\n```")
    }

    @Test("Renders a .divider item as --- even though it has no text content")
    func rendersDividerAsHorizontalRule() {
        let document = makeDocument()
        let before = makeItem(orderKey: "0")
        let divider = makeItem(orderKey: "1")
        let after = makeItem(orderKey: "2")
        let textContents = [
            before.id: TextContent(itemId: before.id, textKind: TextItemKind.paragraph, plainText: "Before"),
            divider.id: TextContent(itemId: divider.id, textKind: TextItemKind.divider, plainText: ""),
            after.id: TextContent(itemId: after.id, textKind: TextItemKind.paragraph, plainText: "After"),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, items: [before, divider, after], textContents: textContents)

        #expect(markdown == "Before\n\n---\n\nAfter")
    }

    @Test("Renders a plain paragraph's plainText unchanged when it has no recorded marks")
    func rendersPlainParagraphTextUnchangedWithNoMarks() {
        let document = makeDocument()
        let item = makeItem(orderKey: "0")
        let textContents = [
            item.id: TextContent(itemId: item.id, textKind: TextItemKind.paragraph, plainText: "No markdown source"),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, items: [item], textContents: textContents)

        #expect(markdown == "No markdown source")
    }

    @Test("Renders all 8 text kinds in orderKey order, joined with blank lines between non-list blocks")
    func rendersAllBlockTypesInOrder() {
        let document = makeDocument()
        let heading = makeItem(orderKey: "0")
        let paragraph = makeItem(orderKey: "1")
        let bullet = makeItem(orderKey: "2")
        let numbered = makeItem(orderKey: "3")
        let checklist = makeItem(orderKey: "4")
        let quote = makeItem(orderKey: "5")
        let code = makeItem(orderKey: "6")
        let divider = makeItem(orderKey: "7")
        let items = [heading, paragraph, bullet, numbered, checklist, quote, code, divider]
        let textContents = [
            heading.id: TextContent(itemId: heading.id, textKind: TextItemKind.heading, plainText: "Heading", headingLevel: 2),
            paragraph.id: TextContent(itemId: paragraph.id, textKind: TextItemKind.paragraph, plainText: "Paragraph"),
            bullet.id: TextContent(itemId: bullet.id, textKind: TextItemKind.bulletedListItem, plainText: "Bullet"),
            numbered.id: TextContent(itemId: numbered.id, textKind: TextItemKind.numberedListItem, plainText: "Numbered"),
            checklist.id: TextContent(itemId: checklist.id, textKind: TextItemKind.checklist, plainText: "Done task", isChecked: true),
            quote.id: TextContent(itemId: quote.id, textKind: TextItemKind.quote, plainText: "Quote"),
            code.id: TextContent(itemId: code.id, textKind: TextItemKind.codeBlock, plainText: "print(1)"),
            divider.id: TextContent(itemId: divider.id, textKind: TextItemKind.divider, plainText: ""),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, items: items, textContents: textContents)

        #expect(markdown == [
            "## Heading",
            "",
            "Paragraph",
            "",
            "- Bullet",
            "",
            "1. Numbered",
            "",
            "- [x] Done task",
            "",
            "> Quote",
            "",
            "```\nprint(1)\n```",
            "",
            "---",
        ].joined(separator: "\n"))
    }

    @Test("Renders an empty item list as an empty string")
    func rendersEmptyBlockListAsEmptyString() {
        let document = makeDocument()

        let markdown = MarkdownExporter.render(documentTitle: document.title, items: [], textContents: [:])

        #expect(markdown.isEmpty)
    }

    // MARK: - TextMark reconstruction (brief 04 review-round regressions)

    @Test("Reconstructs a migrated item's bold/italic/strike/inline-code/link TextMarks back into delimiter-literal Markdown")
    func reconstructsAllMarkTypesFromMigratedContent() {
        let document = makeDocument()
        let item = makeItem(orderKey: "0")
        let plainText = "bold italic strike code link"
        let textContents = [
            item.id: TextContent(itemId: item.id, textKind: TextItemKind.paragraph, plainText: plainText),
        ]
        let marks = [
            TextMark(itemId: item.id, startOffset: 0, endOffset: 4, markType: "bold"),
            TextMark(itemId: item.id, startOffset: 5, endOffset: 11, markType: "italic"),
            TextMark(itemId: item.id, startOffset: 12, endOffset: 18, markType: "strike"),
            TextMark(itemId: item.id, startOffset: 19, endOffset: 23, markType: "inline_code"),
            TextMark(
                itemId: item.id, startOffset: 24, endOffset: 28,
                markType: "link", valueMode: "url", valueText: "https://example.com"
            ),
        ]

        let markdown = MarkdownExporter.render(
            documentTitle: document.title, items: [item], textContents: textContents, marksByItemId: [item.id: marks]
        )

        // Without `TextMarkdownReconstruction` (brief 04's second review
        // bug), this would silently render the unwrapped plain text
        // instead — a migrated document's formatting vanishing on export.
        #expect(markdown == "**bold** *italic* ~~strike~~ `code` [link](https://example.com)")
    }

    @Test("A heading with a bold TextMark reconstructs its formatting inside the heading prefix")
    func reconstructsMarkOnHeadingItem() {
        let document = makeDocument()
        let item = makeItem(orderKey: "0")
        let textContents = [
            item.id: TextContent(itemId: item.id, textKind: TextItemKind.heading, plainText: "Important title", headingLevel: 1),
        ]
        let marks = [TextMark(itemId: item.id, startOffset: 0, endOffset: 9, markType: "bold")]

        let markdown = MarkdownExporter.render(
            documentTitle: document.title, items: [item], textContents: textContents, marksByItemId: [item.id: marks]
        )

        #expect(markdown == "# **Important** title")
    }

    @Test("A TextMark with offsets outside plainText's bounds is skipped rather than corrupting the export")
    func staleOutOfBoundsMarkIsSkipped() {
        let document = makeDocument()
        let item = makeItem(orderKey: "0")
        let textContents = [
            item.id: TextContent(itemId: item.id, textKind: TextItemKind.paragraph, plainText: "short"),
        ]
        // Stale marks left over from an edit that changed plainText
        // without adjusting existing mark offsets (the third brief-04
        // review bug `persistBlock`'s `TextMarkRepository.deleteAll`
        // guards against going forward) — the reconstruction itself must
        // still be defensive against seeing one.
        let marks = [
            TextMark(itemId: item.id, startOffset: 10, endOffset: 20, markType: "bold"),
            TextMark(itemId: item.id, startOffset: 3, endOffset: 1, markType: "italic"),
        ]

        let markdown = MarkdownExporter.render(
            documentTitle: document.title, items: [item], textContents: textContents, marksByItemId: [item.id: marks]
        )

        #expect(markdown == "short")
    }

    @Test("Only contentType == \"text\" items are rendered; a media item is skipped without breaking the export")
    func skipsNonTextItemsWithoutBreakingExport() {
        let document = makeDocument()
        let before = makeItem(orderKey: "0")
        let media = makeItem(orderKey: "1", contentType: "media")
        let after = makeItem(orderKey: "2")
        let textContents = [
            before.id: TextContent(itemId: before.id, textKind: TextItemKind.paragraph, plainText: "Before"),
            after.id: TextContent(itemId: after.id, textKind: TextItemKind.paragraph, plainText: "After"),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, items: [before, media, after], textContents: textContents)

        // Skipping the media item resets the "previous kind" tracking
        // `render` uses to decide whether to insert a blank line
        // (`MarkdownExporter.render`'s doc comment on the loop), so no
        // blank line is inserted before "After" either — the skip is
        // silent, not blank-line-preserving.
        #expect(markdown == "Before\nAfter")
    }
}
