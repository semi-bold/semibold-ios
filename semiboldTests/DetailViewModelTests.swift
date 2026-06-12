import GRDB
import Testing

@testable import semibold

/// Tests for `DetailViewModel`'s `Planning_4_BlockCreateFlow` slice: the
/// first-block bootstrap for a brand-new document, persisting edits to an
/// existing block, and splitting a block in two on Enter.
///
/// These exercise the same repository path the editor relies on
/// end-to-end, against a throwaway in-memory database.
struct DetailViewModelTests {
    private func makeDatabaseManager() -> DatabaseManager {
        DatabaseManager(path: ":memory:")
    }

    @Test("A brand-new document gets one empty paragraph block on load, focused")
    func loadCreatesFirstEmptyBlockForNewDocument() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Untitled"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)

        viewModel.load()

        #expect(viewModel.blocks.count == 1)
        #expect(viewModel.blocks.first?.type == .paragraph)
        #expect(viewModel.blocks.first?.sortOrder == 0)
        #expect(viewModel.focusedBlockId == viewModel.blocks.first?.id)

        // The block is actually persisted, not just held in memory.
        let stored = try blockRepository.blocks(documentId: document.id, parentId: nil)
        #expect(stored.count == 1)
    }

    @Test("Loading a document that already has blocks doesn't add another one")
    func loadDoesNotDuplicateExistingBlocks() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        _ = try blockRepository.create(DocumentBlock(
            documentId: document.id,
            sortOrder: 0,
            type: .paragraph,
            contentJSON: "{\"type\":\"paragraph\",\"text\":[{\"text\":\"Hello\"}]}",
            markdownSource: "Hello"
        ))

        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()

        #expect(viewModel.blocks.count == 1)
        #expect(viewModel.blocks.first?.markdownSource == "Hello")
        #expect(viewModel.focusedBlockId == nil)
    }

    @Test("Editing a block's text persists its markdownSource and contentJSON")
    func updateBlockTextPersists() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "Today was a good day")

        #expect(viewModel.blocks.first?.markdownSource == "Today was a good day")
        #expect(viewModel.blocks.first?.contentJSON.contains("Today was a good day") == true)

        let reloaded = try #require(try blockRepository.find(id: blockId))
        #expect(reloaded.markdownSource == "Today was a good day")
    }

    @Test("Pressing Enter splits the block at the cursor and creates a new block below it, focused")
    func insertBlockSplitsAtCursorAndFocusesNewBlock() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)

        let text = "Hello world"
        // Cursor right after "Hello" (offset 5) — "Hello" stays, " world" moves down.
        viewModel.insertBlock(after: firstBlockId, currentText: text, cursorOffset: 5)

        #expect(viewModel.blocks.count == 2)
        #expect(viewModel.blocks[0].markdownSource == "Hello")
        #expect(viewModel.blocks[0].sortOrder == 0)
        #expect(viewModel.blocks[1].markdownSource == " world")
        #expect(viewModel.blocks[1].sortOrder == 1)
        #expect(viewModel.blocks[1].type == .paragraph)
        #expect(viewModel.focusedBlockId == viewModel.blocks[1].id)

        let stored = try blockRepository.blocks(documentId: document.id, parentId: nil)
        #expect(stored.map(\.markdownSource) == ["Hello", " world"])
    }

    @Test("Pressing Enter at the end of a block creates an empty block below it")
    func insertBlockAtEndCreatesEmptyBlock() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)

        let text = "Hello world"
        viewModel.insertBlock(after: firstBlockId, currentText: text, cursorOffset: text.count)

        #expect(viewModel.blocks.count == 2)
        #expect(viewModel.blocks[0].markdownSource == "Hello world")
        #expect(viewModel.blocks[1].markdownSource == "")
        #expect(viewModel.focusedBlockId == viewModel.blocks[1].id)
    }

    @Test("Pressing Enter on a block that isn't the last shifts later blocks' sortOrder down")
    func insertBlockShiftsLaterBlocksSortOrder() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)

        // Add a second block manually so there's something after the split point.
        let secondBlock = try blockRepository.create(DocumentBlock(
            documentId: document.id,
            sortOrder: 1,
            type: .paragraph,
            contentJSON: "{\"type\":\"paragraph\",\"text\":[{\"text\":\"Second\"}]}",
            markdownSource: "Second"
        ))
        viewModel.load()
        #expect(viewModel.blocks.map(\.id) == [firstBlockId, secondBlock.id])

        viewModel.insertBlock(after: firstBlockId, currentText: "First", cursorOffset: 5)

        #expect(viewModel.blocks.count == 3)
        #expect(viewModel.blocks.map(\.sortOrder) == [0, 1, 2])
        #expect(viewModel.blocks.map(\.markdownSource) == ["First", "", "Second"])

        let stored = try blockRepository.blocks(documentId: document.id, parentId: nil)
        #expect(stored.map(\.markdownSource) == ["First", "", "Second"])
    }
}
