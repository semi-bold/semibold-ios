import Foundation
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
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    @Test("A brand-new document gets one empty paragraph block on load, focused")
    func loadCreatesFirstEmptyBlockForNewDocument() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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

    /// Loads a document with four paragraph blocks ("A", "B", "C", "D")
    /// with `sortOrder` 0, 1, 2, 3, for the drag & drop reorder tests
    /// below (§12.3).
    private func loadFourBlockDocument(
        documentRepository: DocumentRepository,
        blockRepository: DocumentBlockRepository
    ) throws -> (DetailViewModel, [DocumentBlock]) {
        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(firstBlockId, text: "A")
        viewModel.flushPendingChanges()

        for (offset, text) in ["B", "C", "D"].enumerated() {
            _ = try blockRepository.create(DocumentBlock(
                documentId: document.id,
                sortOrder: offset + 1,
                type: .paragraph,
                contentJSON: "{\"type\":\"paragraph\",\"text\":[{\"text\":\"\(text)\"}]}",
                markdownSource: text
            ))
        }
        viewModel.load()
        #expect(viewModel.blocks.map(\.markdownSource) == ["A", "B", "C", "D"])
        #expect(viewModel.blocks.map(\.sortOrder) == [0, 1, 2, 3])

        return (viewModel, viewModel.blocks)
    }

    @Test("reorderBlocks moves a block to a later position and renumbers sortOrder in between")
    func reorderBlocksMovesBlockLaterAndRenumbers() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)
        let (viewModel, _) = try loadFourBlockDocument(documentRepository: documentRepository, blockRepository: blockRepository)

        // Move "B" (index 1) to just after "C" (SwiftUI's onMove
        // `toOffset` semantics: destination index in the pre-removal array).
        viewModel.reorderBlocks(fromOffsets: IndexSet(integer: 1), toOffset: 3)

        #expect(viewModel.blocks.map(\.markdownSource) == ["A", "C", "B", "D"])
        #expect(viewModel.blocks.map(\.sortOrder) == [0, 1, 2, 3])

        let stored = try blockRepository.blocks(documentId: viewModel.document.id, parentId: nil)
        #expect(stored.map(\.markdownSource) == ["A", "C", "B", "D"])
        #expect(stored.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("reorderBlocks moves a block to an earlier position and renumbers sortOrder in between")
    func reorderBlocksMovesBlockEarlierAndRenumbers() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)
        let (viewModel, _) = try loadFourBlockDocument(documentRepository: documentRepository, blockRepository: blockRepository)

        // Move "D" (index 3) to the front.
        viewModel.reorderBlocks(fromOffsets: IndexSet(integer: 3), toOffset: 0)

        #expect(viewModel.blocks.map(\.markdownSource) == ["D", "A", "B", "C"])
        #expect(viewModel.blocks.map(\.sortOrder) == [0, 1, 2, 3])

        let stored = try blockRepository.blocks(documentId: viewModel.document.id, parentId: nil)
        #expect(stored.map(\.markdownSource) == ["D", "A", "B", "C"])
        #expect(stored.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("reorderBlocks to the same position is a no-op that persists nothing new")
    func reorderBlocksToSamePositionIsNoOp() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)
        let (viewModel, _) = try loadFourBlockDocument(documentRepository: documentRepository, blockRepository: blockRepository)

        // Moving index 1 to destination 1 (or 2, which `Array.move`
        // treats as "stay put" when moving a single element forward by
        // one) leaves the order unchanged.
        viewModel.reorderBlocks(fromOffsets: IndexSet(integer: 1), toOffset: 1)

        #expect(viewModel.blocks.map(\.markdownSource) == ["A", "B", "C", "D"])
        #expect(viewModel.blocks.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("reorderBlocks with an empty source does nothing")
    func reorderBlocksWithEmptySourceDoesNothing() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)
        let (viewModel, _) = try loadFourBlockDocument(documentRepository: documentRepository, blockRepository: blockRepository)

        viewModel.reorderBlocks(fromOffsets: IndexSet(), toOffset: 2)

        #expect(viewModel.blocks.map(\.markdownSource) == ["A", "B", "C", "D"])
        #expect(viewModel.blocks.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("moveBlock(id:beforeBlockId:) moves a dragged block to sit just above the drop target")
    func moveBlockBeforeTargetReordersAndPersists() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)
        let (viewModel, blocks) = try loadFourBlockDocument(documentRepository: documentRepository, blockRepository: blockRepository)

        // Drag "A" (first) and drop it onto "C" — "A" should land directly
        // above "C".
        let blockA = blocks[0]
        let blockC = blocks[2]
        viewModel.moveBlock(id: blockA.id, beforeBlockId: blockC.id)

        #expect(viewModel.blocks.map(\.markdownSource) == ["B", "A", "C", "D"])
        #expect(viewModel.blocks.map(\.sortOrder) == [0, 1, 2, 3])

        let stored = try blockRepository.blocks(documentId: viewModel.document.id, parentId: nil)
        #expect(stored.map(\.markdownSource) == ["B", "A", "C", "D"])
        #expect(stored.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("moveBlock(id:beforeBlockId:) moves a dragged block backwards above an earlier target")
    func moveBlockBeforeEarlierTargetReordersAndPersists() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)
        let (viewModel, blocks) = try loadFourBlockDocument(documentRepository: documentRepository, blockRepository: blockRepository)

        // Drag "D" (last) and drop it onto "B" — "D" should land directly
        // above "B".
        let blockB = blocks[1]
        let blockD = blocks[3]
        viewModel.moveBlock(id: blockD.id, beforeBlockId: blockB.id)

        #expect(viewModel.blocks.map(\.markdownSource) == ["A", "D", "B", "C"])
        #expect(viewModel.blocks.map(\.sortOrder) == [0, 1, 2, 3])

        let stored = try blockRepository.blocks(documentId: viewModel.document.id, parentId: nil)
        #expect(stored.map(\.markdownSource) == ["A", "D", "B", "C"])
        #expect(stored.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("moveBlock(id:beforeBlockId:) does nothing when dragging a block onto itself")
    func moveBlockBeforeSelfDoesNothing() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)
        let (viewModel, blocks) = try loadFourBlockDocument(documentRepository: documentRepository, blockRepository: blockRepository)

        viewModel.moveBlock(id: blocks[1].id, beforeBlockId: blocks[1].id)

        #expect(viewModel.blocks.map(\.markdownSource) == ["A", "B", "C", "D"])
        #expect(viewModel.blocks.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("A brand-new document with no content shows the empty-state placeholder")
    func showsEmptyContentPlaceholderForBrandNewDocument() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Untitled"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()

        #expect(viewModel.showsEmptyContentPlaceholder)
    }

    @Test("Typing into the document's only block hides the empty-state placeholder")
    func hidesEmptyContentPlaceholderOnceTextIsTyped() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Untitled"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(firstBlockId, text: "Hello")

        #expect(!viewModel.showsEmptyContentPlaceholder)
    }

    @Test("A document with more than one block doesn't show the empty-state placeholder")
    func hidesEmptyContentPlaceholderWhenMultipleBlocksExist() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)

        // Splitting the empty block into two via Enter leaves two empty
        // paragraph blocks — no longer the single-empty-block state.
        viewModel.insertBlock(after: firstBlockId, currentText: "", cursorOffset: 0)

        #expect(viewModel.blocks.count == 2)
        #expect(!viewModel.showsEmptyContentPlaceholder)
    }

    @Test("Loading a document whose only block already has text doesn't show the empty-state placeholder")
    func hidesEmptyContentPlaceholderForExistingNonEmptyBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

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

        #expect(!viewModel.showsEmptyContentPlaceholder)
    }

    // MARK: - §15.2 error states

    @Test("A failed block save sets errorMessage to the §15.2 '저장 실패' text")
    func persistBlockFailureSetsSaveErrorMessage() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .milliseconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        // Remove the block's row out from under the view model, so the
        // next save (`update`) finds no matching row and throws
        // `RepositoryError.recordNotFound` — simulating a write that fails
        // to persist.
        try blockRepository.hardDelete(id: blockId)

        #expect(viewModel.errorMessage == nil)

        // `mergeOrDeleteBlock` on the only block does nothing (PLANNING's
        // "every document keeps ≥1 block" invariant), so use a keyboard
        // shortcut's immediate-persist path instead — toggling bold on an
        // empty block does nothing, so give it text first via the
        // structural Heading conversion, which also persists immediately.
        viewModel.convertBlockToHeading(blockId, level: 1)

        #expect(viewModel.errorMessage == AppErrorMessages.saveFailed)
    }

    @Test("A failed block delete sets errorMessage to the §15.2 '삭제 실패' text")
    func mergeOrDeleteBlockFailureSetsDeleteErrorMessage() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let firstBlockId = try #require(viewModel.blocks.first?.id)

        // Create a second, empty block below the first so Backspace-at-start
        // on it has something to merge/delete into.
        viewModel.insertBlock(after: firstBlockId, currentText: "", cursorOffset: 0)
        let secondBlockId = try #require(viewModel.blocks.last?.id)

        // Detach the in-memory store from its coordinator so the
        // soft-delete's `context.save()` call throws instead of
        // succeeding — the Core Data equivalent of closing the underlying
        // database connection out from under a pending write.
        try store.simulateStoreFailure()

        #expect(viewModel.errorMessage == nil)

        viewModel.mergeOrDeleteBlock(secondBlockId, currentText: "")

        #expect(viewModel.errorMessage == AppErrorMessages.deleteFailed)
    }
}
