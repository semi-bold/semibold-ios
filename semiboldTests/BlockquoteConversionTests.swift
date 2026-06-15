import GRDB
import Testing

@testable import semibold

/// Tests for `DetailViewModel.updateBlockText`'s blockquote conversion
/// (`markdown-phase4` AC4): typing `> ` converts a paragraph block to
/// `.blockquote`, persisted immediately.
///
/// Split out from `DetailViewModelTests` (which covers the rest of
/// `DetailViewModel`'s editing/reorder behavior) to keep each suite's body
/// within SwiftLint's `type_body_length`, following AC3's
/// `ChecklistConversionTests` precedent.
@MainActor
struct BlockquoteConversionTests {
    private func makeDatabaseManager() -> DatabaseManager {
        DatabaseManager(path: ":memory:")
    }

    @Test("Typing '> quote' converts the block to a blockquote, saved immediately")
    func typingBlockquotePrefixConvertsBlockToBlockquote() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            // A long debounce makes sure the blockquote conversion below is
            // persisted immediately, not via the debounced path.
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "> Quote")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .blockquote)
        #expect(block.displayText == "Quote")
        #expect(block.contentJSON.contains("\"type\":\"blockquote\""))
        #expect(block.contentJSON.contains("Quote"))

        // markdownSource keeps the literal Markdown the user typed, for
        // round-tripping (§8.1).
        #expect(block.markdownSource == "> Quote")

        // Type conversion is a structural change — persisted immediately,
        // not waiting for the (long) debounce interval above.
        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.type == .blockquote)
        #expect(stored.displayText == "Quote")
        #expect(stored.markdownSource == "> Quote")
    }

    @Test("Editing a blockquote keeps it a blockquote and rebuilds markdownSource with the '> ' prefix")
    func editingBlockquoteRebuildsMarkdownSource() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .milliseconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "> Quote")
        // Continue typing in the now-blockquote block — the displayed text
        // (no '> ') is what `ParagraphTextField` reports back.
        viewModel.updateBlockText(blockId, text: "Quote, revised")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .blockquote)
        #expect(block.displayText == "Quote, revised")
        #expect(block.markdownSource == "> Quote, revised")
        #expect(block.contentJSON.contains("Quote, revised"))
    }

    @Test("'>quote' (no space) does NOT convert to a blockquote")
    func noSpaceAfterAngleBracketDoesNotConvert() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: ">quote")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == ">quote")
    }

    @Test("'>> quote' (second character isn't a space) does NOT convert to a blockquote")
    func doubleAngleBracketDoesNotConvert() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: ">> quote")

        let block = try #require(viewModel.blocks.first)
        // ">> quote" doesn't match "> " (its 2nd character is ">", not a
        // space), so it stays a plain paragraph — same precedent as AC2's
        // "-- item" not matching "- ".
        #expect(block.type == .paragraph)
        #expect(block.displayText == ">> quote")
    }

    @Test("'> ' blockquote prefix doesn't conflict with heading/list/checklist prefixes")
    func blockquotePrefixDoesNotConflictWithOtherPrefixes() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))

        for typedText in ["# Title", "- item", "1. item", "- [ ] task"] {
            let block = try blockRepository.create(
                DocumentBlock(
                    documentId: document.id,
                    sortOrder: 0,
                    type: .paragraph,
                    contentJSON: BlockContent.paragraphJSON(text: "")
                )
            )
            let viewModel = DetailViewModel(
                document: document,
                documentBlockRepository: blockRepository,
                autosaveDebounceInterval: .seconds(10)
            )
            viewModel.load()

            viewModel.updateBlockText(block.id, text: typedText)

            let converted = try #require(viewModel.blocks.first(where: { $0.id == block.id }))
            #expect(converted.type != .blockquote)
        }
    }
}
