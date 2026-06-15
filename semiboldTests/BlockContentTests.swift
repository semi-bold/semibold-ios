import Testing

@testable import semibold

/// Round-trip tests for `BlockContent`'s `contentJSON` encode/decode —
/// the `{ type, text: RichTextSpan[] }` (and `heading`'s extra `level`)
/// shapes from `tasks/NO-001.md` §8.1, used by `DetailViewModel` to build
/// and read back a block's `contentJSON`.
struct BlockContentTests {
    @Test("Paragraph content round-trips through contentJSON")
    func paragraphRoundTrips() throws {
        let json = BlockContent.paragraphJSON(text: "Hello world")

        #expect(json.contains("\"type\":\"paragraph\""))
        #expect(json.contains("Hello world"))

        let decoded = BlockContent.decode(from: json, type: .paragraph)
        #expect(decoded == .paragraph(ParagraphContent(text: [RichTextSpan(text: "Hello world")])))
        #expect(decoded.text.map(\.text) == ["Hello world"])
    }

    @Test("Heading content round-trips through contentJSON, carrying its level")
    func headingRoundTrips() throws {
        for level in 1...3 {
            let json = BlockContent.headingJSON(level: level, text: "Title")

            #expect(json.contains("\"type\":\"heading\""))
            #expect(json.contains("\"level\":\(level)"))
            #expect(json.contains("Title"))

            let decoded = BlockContent.decode(from: json, type: .heading)
            #expect(decoded == .heading(HeadingContent(level: level, text: [RichTextSpan(text: "Title")])))
            #expect(decoded.text.map(\.text) == ["Title"])
        }
    }

    @Test("decode falls back to an empty paragraph for malformed JSON")
    func decodeFallsBackOnMalformedJSON() throws {
        let decoded = BlockContent.decode(from: "not json", type: .paragraph)
        #expect(decoded == .paragraph(ParagraphContent(text: [])))
    }

    @Test("DocumentBlock.displayText reflects contentJSON, not markdownSource")
    func displayTextReflectsContentJSON() throws {
        let heading = DocumentBlock(
            documentId: "doc",
            type: .heading,
            contentJSON: BlockContent.headingJSON(level: 2, text: "Today"),
            markdownSource: "## Today"
        )

        #expect(heading.displayText == "Today")
        #expect(heading.headingLevel == 2)
        #expect(heading.markdownSource == "## Today")

        let paragraph = DocumentBlock(
            documentId: "doc",
            type: .paragraph,
            contentJSON: BlockContent.paragraphJSON(text: "Plain text"),
            markdownSource: "Plain text"
        )

        #expect(paragraph.displayText == "Plain text")
        #expect(paragraph.headingLevel == nil)
    }

    @Test("Bulleted list item content round-trips through contentJSON")
    func bulletedListItemRoundTrips() throws {
        let json = BlockContent.bulletedListItemJSON(text: "Buy milk")

        #expect(json.contains("\"type\":\"bulleted_list_item\""))
        #expect(json.contains("Buy milk"))

        let decoded = BlockContent.decode(from: json, type: .bulletedListItem)
        #expect(
            decoded == .bulletedListItem(
                ListItemContent(type: "bulleted_list_item", text: [RichTextSpan(text: "Buy milk")])
            )
        )
        #expect(decoded.text.map(\.text) == ["Buy milk"])
    }

    @Test("Numbered list item content round-trips through contentJSON")
    func numberedListItemRoundTrips() throws {
        let json = BlockContent.numberedListItemJSON(text: "Step one")

        #expect(json.contains("\"type\":\"numbered_list_item\""))
        #expect(json.contains("Step one"))

        let decoded = BlockContent.decode(from: json, type: .numberedListItem)
        #expect(
            decoded == .numberedListItem(
                ListItemContent(type: "numbered_list_item", text: [RichTextSpan(text: "Step one")])
            )
        )
        #expect(decoded.text.map(\.text) == ["Step one"])
    }

    @Test("Checklist item content round-trips through contentJSON, carrying its checked state")
    func checklistItemRoundTrips() throws {
        for checked in [false, true] {
            let json = BlockContent.checklistItemJSON(checked: checked, text: "Buy milk")

            #expect(json.contains("\"type\":\"checklist_item\""))
            #expect(json.contains("\"checked\":\(checked)"))
            #expect(json.contains("Buy milk"))

            let decoded = BlockContent.decode(from: json, type: .checklistItem)
            #expect(decoded == .checklistItem(ChecklistItemContent(checked: checked, text: [RichTextSpan(text: "Buy milk")])))
            #expect(decoded.text.map(\.text) == ["Buy milk"])
        }
    }

    @Test("DocumentBlock.displayText/isChecked reflect checklist-item contentJSON/markdownSource")
    func displayTextAndCheckedReflectChecklistItems() throws {
        let unchecked = DocumentBlock(
            documentId: "doc",
            type: .checklistItem,
            contentJSON: BlockContent.checklistItemJSON(checked: false, text: "Buy milk"),
            markdownSource: "- [ ] Buy milk"
        )

        #expect(unchecked.displayText == "Buy milk")
        #expect(unchecked.isChecked == false)

        let checked = DocumentBlock(
            documentId: "doc",
            type: .checklistItem,
            contentJSON: BlockContent.checklistItemJSON(checked: true, text: "Buy milk"),
            markdownSource: "- [x] Buy milk"
        )

        #expect(checked.displayText == "Buy milk")
        #expect(checked.isChecked == true)

        // Non-checklist blocks always read as not checked.
        let paragraph = DocumentBlock(
            documentId: "doc",
            type: .paragraph,
            contentJSON: BlockContent.paragraphJSON(text: "Plain text"),
            markdownSource: "Plain text"
        )

        #expect(paragraph.isChecked == false)
    }

    @Test("Blockquote content round-trips through contentJSON")
    func blockquoteRoundTrips() throws {
        let json = BlockContent.blockquoteJSON(text: "A wise quote")

        #expect(json.contains("\"type\":\"blockquote\""))
        #expect(json.contains("A wise quote"))

        let decoded = BlockContent.decode(from: json, type: .blockquote)
        #expect(decoded == .blockquote(BlockquoteContent(text: [RichTextSpan(text: "A wise quote")])))
        #expect(decoded.text.map(\.text) == ["A wise quote"])
    }

    @Test("DocumentBlock.displayText reflects blockquote contentJSON/markdownSource")
    func displayTextReflectsBlockquote() throws {
        let blockquote = DocumentBlock(
            documentId: "doc",
            type: .blockquote,
            contentJSON: BlockContent.blockquoteJSON(text: "A wise quote"),
            markdownSource: "> A wise quote"
        )

        #expect(blockquote.displayText == "A wise quote")
        #expect(blockquote.markdownSource == "> A wise quote")
        #expect(blockquote.headingLevel == nil)
    }

    @Test("Code block content round-trips through contentJSON, carrying its language")
    func codeBlockRoundTrips() throws {
        let json = BlockContent.codeBlockJSON(language: "swift", code: "let x = 1")

        #expect(json.contains("\"type\":\"code_block\""))
        #expect(json.contains("\"language\":\"swift\""))
        #expect(json.contains("let x = 1"))

        let decoded = BlockContent.decode(from: json, type: .codeBlock)
        #expect(decoded == .codeBlock(CodeBlockContent(language: "swift", code: "let x = 1")))
        #expect(decoded.text.map(\.text) == ["let x = 1"])
    }

    @Test("Code block content with no language round-trips, decoding 'language' as nil")
    func codeBlockWithNoLanguageRoundTrips() throws {
        let json = BlockContent.codeBlockJSON(language: nil, code: "echo hi")

        #expect(json.contains("\"type\":\"code_block\""))
        #expect(!json.contains("\"language\""))
        #expect(json.contains("echo hi"))

        let decoded = BlockContent.decode(from: json, type: .codeBlock)
        #expect(decoded == .codeBlock(CodeBlockContent(language: nil, code: "echo hi")))
        #expect(decoded.text.map(\.text) == ["echo hi"])
    }

    @Test("DocumentBlock.displayText/codeLanguage reflect code-block contentJSON/markdownSource")
    func displayTextAndLanguageReflectCodeBlock() throws {
        let withLanguage = DocumentBlock(
            documentId: "doc",
            type: .codeBlock,
            contentJSON: BlockContent.codeBlockJSON(language: "swift", code: "let x = 1"),
            markdownSource: "```swift\nlet x = 1\n```"
        )

        #expect(withLanguage.displayText == "let x = 1")
        #expect(withLanguage.codeLanguage == "swift")
        #expect(withLanguage.headingLevel == nil)

        let withoutLanguage = DocumentBlock(
            documentId: "doc",
            type: .codeBlock,
            contentJSON: BlockContent.codeBlockJSON(language: nil, code: "echo hi"),
            markdownSource: "```\necho hi\n```"
        )

        #expect(withoutLanguage.displayText == "echo hi")
        #expect(withoutLanguage.codeLanguage == nil)

        // Non-code blocks always read as having no code language.
        let paragraph = DocumentBlock(
            documentId: "doc",
            type: .paragraph,
            contentJSON: BlockContent.paragraphJSON(text: "Plain text"),
            markdownSource: "Plain text"
        )

        #expect(paragraph.codeLanguage == nil)
    }

    @Test("DocumentBlock.displayText/numberedListNumber reflect list-item contentJSON/markdownSource")
    func displayTextAndNumberReflectListItems() throws {
        let bulleted = DocumentBlock(
            documentId: "doc",
            type: .bulletedListItem,
            contentJSON: BlockContent.bulletedListItemJSON(text: "Milk"),
            markdownSource: "- Milk"
        )

        #expect(bulleted.displayText == "Milk")
        #expect(bulleted.numberedListNumber == nil)

        let numbered = DocumentBlock(
            documentId: "doc",
            type: .numberedListItem,
            contentJSON: BlockContent.numberedListItemJSON(text: "First step"),
            markdownSource: "1. First step"
        )

        #expect(numbered.displayText == "First step")
        #expect(numbered.numberedListNumber == 1)

        let numberedFive = DocumentBlock(
            documentId: "doc",
            type: .numberedListItem,
            contentJSON: BlockContent.numberedListItemJSON(text: "Fifth step"),
            markdownSource: "5. Fifth step"
        )

        #expect(numberedFive.numberedListNumber == 5)
    }
}
