import GRDB
import Testing

@testable import semibold

/// Tests for `DetailViewModel`'s `Planning_4_BlockCreateFlow` slice: the
/// first-block bootstrap for a brand-new document, persisting edits to an
/// existing block, and splitting a block in two on Enter.
///
/// These exercise the same repository path the editor relies on
/// end-to-end, against a throwaway in-memory database.
///
/// `DetailViewModel` is `@MainActor`-isolated (it mutates `@Observable`
/// state from a debounced background `Task`, like the real editor would),
/// so this suite runs on the main actor too.
@MainActor
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

    @Test("Editing a block's text updates it in memory immediately and persists it once the debounce settles")
    func updateBlockTextPersistsAfterDebounce() async throws {
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

        viewModel.updateBlockText(blockId, text: "Today was a good day")

        // In-memory state updates immediately, before the debounced save runs.
        #expect(viewModel.blocks.first?.markdownSource == "Today was a good day")
        #expect(viewModel.blocks.first?.contentJSON.contains("Today was a good day") == true)

        // The database write hasn't happened yet — debounced, not immediate.
        let beforeDebounce = try blockRepository.find(id: blockId)
        #expect(beforeDebounce?.markdownSource != "Today was a good day")

        try await Task.sleep(for: .milliseconds(50))

        let reloaded = try #require(try blockRepository.find(id: blockId))
        #expect(reloaded.markdownSource == "Today was a good day")
    }

    @Test("Backgrounding the app flushes a pending debounced edit immediately")
    func flushPendingChangesPersistsImmediately() throws {
        let database = makeDatabaseManager()
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

        viewModel.updateBlockText(blockId, text: "Saved before backgrounding")
        viewModel.flushPendingChanges()

        let reloaded = try #require(try blockRepository.find(id: blockId))
        #expect(reloaded.markdownSource == "Saved before backgrounding")
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

    @Test("Backspace at the start of an empty block deletes it and focuses the previous block at its end")
    func backspaceAtStartOfEmptyBlockDeletesItAndFocusesPreviousBlockEnd() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)

        // Add a second, empty block right below the first.
        let secondBlock = try blockRepository.create(DocumentBlock(
            documentId: document.id,
            sortOrder: 1,
            type: .paragraph,
            contentJSON: "{\"type\":\"paragraph\",\"text\":[{\"text\":\"\"}]}",
            markdownSource: ""
        ))
        // A third block follows, to check sortOrder shifting after delete.
        let thirdBlock = try blockRepository.create(DocumentBlock(
            documentId: document.id,
            sortOrder: 2,
            type: .paragraph,
            contentJSON: "{\"type\":\"paragraph\",\"text\":[{\"text\":\"Third\"}]}",
            markdownSource: "Third"
        ))
        viewModel.load()
        viewModel.updateBlockText(firstBlockId, text: "First")

        viewModel.mergeOrDeleteBlock(secondBlock.id, currentText: "")

        #expect(viewModel.blocks.map(\.id) == [firstBlockId, thirdBlock.id])
        #expect(viewModel.blocks.map(\.sortOrder) == [0, 1])
        #expect(viewModel.blocks[0].markdownSource == "First")
        #expect(viewModel.focusedBlockId == firstBlockId)
        #expect(viewModel.focusedBlockCursorOffset == "First".utf16.count)

        // The empty block is soft-deleted, not just dropped in memory.
        let stored = try blockRepository.blocks(documentId: document.id, parentId: nil)
        #expect(stored.map(\.id) == [firstBlockId, thirdBlock.id])
        #expect(stored.map(\.sortOrder) == [0, 1])

        let deleted = try blockRepository.find(id: secondBlock.id)
        #expect(deleted?.deletedAt != nil)
    }

    @Test("Backspace at the start of a non-empty block merges its text into the previous block")
    func backspaceAtStartOfNonEmptyBlockMergesIntoPreviousBlock() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(firstBlockId, text: "Hello")
        viewModel.flushPendingChanges()

        let secondBlock = try blockRepository.create(DocumentBlock(
            documentId: document.id,
            sortOrder: 1,
            type: .paragraph,
            contentJSON: "{\"type\":\"paragraph\",\"text\":[{\"text\":\" world\"}]}",
            markdownSource: " world"
        ))
        viewModel.load()
        #expect(viewModel.blocks.map(\.id) == [firstBlockId, secondBlock.id])

        viewModel.mergeOrDeleteBlock(secondBlock.id, currentText: " world")

        #expect(viewModel.blocks.count == 1)
        #expect(viewModel.blocks[0].id == firstBlockId)
        #expect(viewModel.blocks[0].markdownSource == "Hello world")
        #expect(viewModel.focusedBlockId == firstBlockId)
        // Caret lands at the seam between "Hello" and " world".
        #expect(viewModel.focusedBlockCursorOffset == "Hello".utf16.count)

        let stored = try blockRepository.blocks(documentId: document.id, parentId: nil)
        #expect(stored.map(\.markdownSource) == ["Hello world"])

        let deleted = try blockRepository.find(id: secondBlock.id)
        #expect(deleted?.deletedAt != nil)
    }

    @Test("Backspace at the start of the document's first block does nothing")
    func backspaceAtStartOfFirstBlockDoesNothing() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(firstBlockId, text: "Only block")
        // Clear the focus state `load()`'s bootstrap set, so the assertion
        // below reflects `mergeOrDeleteBlock`'s own behavior rather than a
        // leftover from loading a brand-new document.
        viewModel.focusHandled()

        viewModel.mergeOrDeleteBlock(firstBlockId, currentText: "Only block")

        #expect(viewModel.blocks.count == 1)
        #expect(viewModel.blocks[0].id == firstBlockId)
        #expect(viewModel.focusedBlockId == nil)
    }

    @Test("moveBlock swaps a block with the neighbor above it and persists the new order")
    func moveBlockUpSwapsSortOrderAndPersists() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(firstBlockId, text: "First")
        viewModel.flushPendingChanges()

        let secondBlock = try blockRepository.create(DocumentBlock(
            documentId: document.id,
            sortOrder: 1,
            type: .paragraph,
            contentJSON: "{\"type\":\"paragraph\",\"text\":[{\"text\":\"Second\"}]}",
            markdownSource: "Second"
        ))
        viewModel.load()
        #expect(viewModel.blocks.map(\.markdownSource) == ["First", "Second"])

        viewModel.moveBlock(id: secondBlock.id, direction: .up)

        #expect(viewModel.blocks.map(\.markdownSource) == ["Second", "First"])
        #expect(viewModel.blocks.map(\.sortOrder) == [0, 1])

        let stored = try blockRepository.blocks(documentId: document.id, parentId: nil)
        #expect(stored.map(\.markdownSource) == ["Second", "First"])
        #expect(stored.map(\.sortOrder) == [0, 1])
    }

    @Test("moveBlock does nothing when the block is already at the top or bottom")
    func moveBlockAtBoundaryDoesNothing() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(firstBlockId, text: "Only block")

        viewModel.moveBlock(id: firstBlockId, direction: .up)
        #expect(viewModel.blocks.map(\.markdownSource) == ["Only block"])

        viewModel.moveBlock(id: firstBlockId, direction: .down)
        #expect(viewModel.blocks.map(\.markdownSource) == ["Only block"])
    }
}
