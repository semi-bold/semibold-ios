import Foundation
import Testing

@testable import semibold

/// Tests for `MarkdownExporter.render` — §10.3's "Markdown Renderer" /
/// "`.md` 문자열 생성" step, given a `Document` and its already-ordered
/// `[DocumentBlock]`s.
struct MarkdownExporterTests {
    private func makeDocument() -> Document {
        Document(title: "Diary")
    }

    private func makeBlock(
        sortOrder: Int,
        type: BlockType,
        contentJSON: String,
        markdownSource: String?
    ) -> DocumentBlock {
        DocumentBlock(
            documentId: "doc-1",
            sortOrder: sortOrder,
            type: type,
            contentJSON: contentJSON,
            markdownSource: markdownSource
        )
    }

    @Test("Renders a heading followed by a paragraph with a blank line between them")
    func rendersHeadingAndParagraphWithBlankLineBetween() {
        let document = makeDocument()
        let blocks = [
            makeBlock(
                sortOrder: 0,
                type: .heading,
                contentJSON: BlockContent.headingJSON(level: 1, text: "Title"),
                markdownSource: "# Title"
            ),
            makeBlock(
                sortOrder: 1,
                type: .paragraph,
                contentJSON: BlockContent.paragraphJSON(text: "Hello world"),
                markdownSource: "Hello world"
            ),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, blocks: blocks)

        #expect(markdown == "# Title\n\nHello world")
    }

    @Test("Renders consecutive bulleted list items on adjacent lines, no blank line between them")
    func rendersConsecutiveBulletedListItemsWithoutBlankLines() {
        let document = makeDocument()
        let blocks = [
            makeBlock(
                sortOrder: 0,
                type: .paragraph,
                contentJSON: BlockContent.paragraphJSON(text: "Shopping list"),
                markdownSource: "Shopping list"
            ),
            makeBlock(
                sortOrder: 1,
                type: .bulletedListItem,
                contentJSON: BlockContent.bulletedListItemJSON(text: "Milk"),
                markdownSource: "- Milk"
            ),
            makeBlock(
                sortOrder: 2,
                type: .bulletedListItem,
                contentJSON: BlockContent.bulletedListItemJSON(text: "Eggs"),
                markdownSource: "- Eggs"
            ),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, blocks: blocks)

        #expect(markdown == "Shopping list\n\n- Milk\n- Eggs")
    }

    @Test("Renders consecutive numbered list items without blank lines, but checklist items in a separate run")
    func rendersNumberedListThenChecklistWithBlankLineBetweenFamilies() {
        let document = makeDocument()
        let blocks = [
            makeBlock(
                sortOrder: 0,
                type: .numberedListItem,
                contentJSON: BlockContent.numberedListItemJSON(text: "First"),
                markdownSource: "1. First"
            ),
            makeBlock(
                sortOrder: 1,
                type: .numberedListItem,
                contentJSON: BlockContent.numberedListItemJSON(text: "Second"),
                markdownSource: "2. Second"
            ),
            makeBlock(
                sortOrder: 2,
                type: .checklistItem,
                contentJSON: BlockContent.checklistItemJSON(checked: false, text: "Task"),
                markdownSource: "- [ ] Task"
            ),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, blocks: blocks)

        #expect(markdown == "1. First\n2. Second\n\n- [ ] Task")
    }

    @Test("Renders a blockquote and a code block surrounded by blank lines")
    func rendersBlockquoteAndCodeBlockWithBlankLines() {
        let document = makeDocument()
        let blocks = [
            makeBlock(
                sortOrder: 0,
                type: .blockquote,
                contentJSON: BlockContent.blockquoteJSON(text: "Wise words"),
                markdownSource: "> Wise words"
            ),
            makeBlock(
                sortOrder: 1,
                type: .codeBlock,
                contentJSON: BlockContent.codeBlockJSON(language: "swift", code: "let x = 1"),
                markdownSource: "```swift\nlet x = 1\n```"
            ),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, blocks: blocks)

        #expect(markdown == "> Wise words\n\n```swift\nlet x = 1\n```")
    }

    @Test("Renders a .divider block as --- even though it has no markdownSource")
    func rendersDividerAsHorizontalRule() {
        let document = makeDocument()
        let blocks = [
            makeBlock(
                sortOrder: 0,
                type: .paragraph,
                contentJSON: BlockContent.paragraphJSON(text: "Before"),
                markdownSource: "Before"
            ),
            makeBlock(
                sortOrder: 1,
                type: .divider,
                contentJSON: BlockContent.dividerJSON(),
                markdownSource: nil
            ),
            makeBlock(
                sortOrder: 2,
                type: .paragraph,
                contentJSON: BlockContent.paragraphJSON(text: "After"),
                markdownSource: "After"
            ),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, blocks: blocks)

        #expect(markdown == "Before\n\n---\n\nAfter")
    }

    @Test("Falls back to displayText when a non-divider block's markdownSource is nil")
    func fallsBackToDisplayTextWhenMarkdownSourceIsNil() {
        let document = makeDocument()
        let blocks = [
            makeBlock(
                sortOrder: 0,
                type: .paragraph,
                contentJSON: BlockContent.paragraphJSON(text: "No markdown source"),
                markdownSource: nil
            ),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, blocks: blocks)

        #expect(markdown == "No markdown source")
    }

    @Test("Renders all 8 block types in sortOrder, joined with blank lines between non-list blocks")
    func rendersAllBlockTypesInOrder() {
        let document = makeDocument()
        let blocks = [
            makeBlock(
                sortOrder: 0,
                type: .heading,
                contentJSON: BlockContent.headingJSON(level: 2, text: "Heading"),
                markdownSource: "## Heading"
            ),
            makeBlock(
                sortOrder: 1,
                type: .paragraph,
                contentJSON: BlockContent.paragraphJSON(text: "Paragraph"),
                markdownSource: "Paragraph"
            ),
            makeBlock(
                sortOrder: 2,
                type: .bulletedListItem,
                contentJSON: BlockContent.bulletedListItemJSON(text: "Bullet"),
                markdownSource: "- Bullet"
            ),
            makeBlock(
                sortOrder: 3,
                type: .numberedListItem,
                contentJSON: BlockContent.numberedListItemJSON(text: "Numbered"),
                markdownSource: "1. Numbered"
            ),
            makeBlock(
                sortOrder: 4,
                type: .checklistItem,
                contentJSON: BlockContent.checklistItemJSON(checked: true, text: "Done task"),
                markdownSource: "- [x] Done task"
            ),
            makeBlock(
                sortOrder: 5,
                type: .blockquote,
                contentJSON: BlockContent.blockquoteJSON(text: "Quote"),
                markdownSource: "> Quote"
            ),
            makeBlock(
                sortOrder: 6,
                type: .codeBlock,
                contentJSON: BlockContent.codeBlockJSON(language: nil, code: "print(1)"),
                markdownSource: "```\nprint(1)\n```"
            ),
            makeBlock(
                sortOrder: 7,
                type: .divider,
                contentJSON: BlockContent.dividerJSON(),
                markdownSource: nil
            ),
        ]

        let markdown = MarkdownExporter.render(documentTitle: document.title, blocks: blocks)

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

    @Test("Renders an empty block list as an empty string")
    func rendersEmptyBlockListAsEmptyString() {
        let document = makeDocument()

        let markdown = MarkdownExporter.render(documentTitle: document.title, blocks: [])

        #expect(markdown.isEmpty)
    }
}
