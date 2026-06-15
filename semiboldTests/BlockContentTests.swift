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
}
