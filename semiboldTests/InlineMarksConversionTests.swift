import GRDB
import Testing

@testable import semibold

/// End-to-end tests for `DetailViewModel.updateBlockText`'s inline-mark
/// parsing (`markdown-phase4` AC6): typing `**bold**`/`*italic*`/
/// `~~strike~~`/`` `code` ``/`[text](url)` within a block's text produces a
/// `contentJSON.text` of multiple `RichTextSpan`s with the matching
/// `marks`/`href`, while `displayText` (what the editor shows/edits) stays
/// the literally-typed text.
///
/// Split out from `DetailViewModelTests`/`*ConversionTests`, following the
/// AC3 "per-topic test file" convention — this AC's parsing applies across
/// every `[RichTextSpan]`-based block type (paragraph, heading, list items,
/// checklist, blockquote), not just one type conversion.
@MainActor
struct InlineMarksConversionTests {
    private func makeDatabaseManager() throws -> DatabaseManager {
        try DatabaseManager(path: ":memory:")
    }

    @Test("Typing '**bold** text' into a paragraph block produces a bold span and a plain span")
    func boldTextInParagraphProducesMarkedSpans() throws {
        let database = try makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "**bold** text")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)

        let content = BlockContent.decode(from: block.contentJSON, type: .paragraph)
        #expect(content.text == [
            RichTextSpan(text: "**bold**", marks: [.bold]),
            RichTextSpan(text: " text")
        ])

        // displayText stays the literally-typed text (with delimiters) so
        // the editor's UITextView isn't fighting what the user typed.
        #expect(block.displayText == "**bold** text")
    }

    @Test("Typing inline marks (italic, strike, inline code, link) produces the matching marked spans")
    func variousInlineMarksProduceMatchingSpans() throws {
        let database = try makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "*italic* and ~~strike~~ and `code` and [link](https://example.com)")

        let block = try #require(viewModel.blocks.first)
        let content = BlockContent.decode(from: block.contentJSON, type: .paragraph)
        #expect(content.text == [
            RichTextSpan(text: "*italic*", marks: [.italic]),
            RichTextSpan(text: " and "),
            RichTextSpan(text: "~~strike~~", marks: [.strike]),
            RichTextSpan(text: " and "),
            RichTextSpan(text: "`code`", marks: [.inlineCode]),
            RichTextSpan(text: " and "),
            RichTextSpan(text: "[link](https://example.com)", marks: [.link], href: "https://example.com")
        ])
    }

    @Test("Inline marks compose with heading conversion — typing '# **bold** title' produces a heading with a bold span")
    func inlineMarksComposeWithHeadingConversion() throws {
        let database = try makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "# **bold** title")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .heading)
        #expect(block.headingLevel == 1)
        #expect(block.displayText == "**bold** title")

        let content = BlockContent.decode(from: block.contentJSON, type: .heading)
        #expect(content.text == [
            RichTextSpan(text: "**bold**", marks: [.bold]),
            RichTextSpan(text: " title")
        ])
    }

    @Test("Typing 'plain' (no Markdown syntax) keeps a single unmarked span")
    func plainTextStaysUnmarked() throws {
        let database = try makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "plain text")

        let block = try #require(viewModel.blocks.first)
        let content = BlockContent.decode(from: block.contentJSON, type: .paragraph)
        #expect(content.text == [RichTextSpan(text: "plain text")])
    }
}
