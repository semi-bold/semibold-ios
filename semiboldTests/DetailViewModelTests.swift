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
///
/// **NO-005 model note**: rewritten against the `DocumentItem`/
/// `TextContent` model (`tasks/NO-005.md` §3) that replaced
/// `DocumentBlock`/`DocumentBlockRepository` — same typed-input/assertions
/// as before, translated to the new schema's vocabulary. Two deliberate
/// deviations from the pre-NO-005 assertions, both because the new model
/// genuinely behaves differently (not just renamed):
/// - There's no integer `sortOrder` to assert on anymore — `DocumentItem
///   .orderKey` is a string-based fractional index (`tasks/NO-005.md`
///   §2.2), so "is the list in the right order" is checked via each
///   item's `plainText` (through `viewModel.textContent(forItemId:)`)
///   read back in `items` array order, the same way a reader of the
///   editor would notice a wrong order — not via a literal numbering
///   scheme.
/// - `insertBlockShiftsLaterBlocksSortOrder` below (renamed
///   `insertBlockDoesNotDisturbLaterSiblingsOrderKey`) now asserts the
///   opposite of its old name: `orderKey`'s whole point is that
///   inserting a new sibling never has to renumber anyone else
///   (`DetailViewModel.insertBlock`'s doc comment), unlike the old
///   integer `sortOrder`, which had to shift every later block down by
///   one. The externally-visible result (correct display order) is
///   unchanged; only the internal mechanism is asserted differently.
@MainActor
struct DetailViewModelTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    private func makeViewModel(
        document: Document,
        store: CoreDataTestStore,
        autosaveDebounceInterval: Duration = .milliseconds(500)
    ) -> DetailViewModel {
        DetailViewModel(
            document: document,
            documentItemRepository: DocumentItemRepository(context: store.context),
            textItemRepository: TextItemRepository(context: store.context),
            textMarkRepository: TextMarkRepository(context: store.context),
            mediaItemRepository: MediaItemRepository(context: store.context),
            folderRepository: FolderRepository(context: store.context),
            autosaveDebounceInterval: autosaveDebounceInterval
        )
    }

    /// The persisted plain text of `documentId`'s top-level items, in
    /// display order — the "read it back from the database" counterpart
    /// to `viewModel.items.map { viewModel.textContent(forItemId: $0.id)
    /// .plainText }`, used to confirm an edit actually reached storage
    /// and not just the in-memory view model.
    private func storedPlainTexts(
        documentId: String,
        documentItemRepository: DocumentItemRepository,
        textItemRepository: TextItemRepository
    ) throws -> [String] {
        let items = try documentItemRepository.children(documentId: documentId, parentItemId: nil)
        return try items.map { try textItemRepository.find(itemId: $0.id)?.plainText ?? "" }
    }

    @Test("A brand-new document gets one empty paragraph block on load, focused")
    func loadCreatesFirstEmptyBlockForNewDocument() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Untitled"))
        let viewModel = makeViewModel(document: document, store: store)

        viewModel.load()

        #expect(viewModel.items.count == 1)
        #expect(viewModel.textContent(forItemId: viewModel.items[0].id).textKind == TextItemKind.paragraph)
        #expect(viewModel.focusedBlockId == viewModel.items.first?.id)

        // The item is actually persisted, not just held in memory.
        let stored = try documentItemRepository.children(documentId: document.id, parentItemId: nil)
        #expect(stored.count == 1)
    }

    @Test("Loading a document that already has blocks doesn't add another one")
    func loadDoesNotDuplicateExistingBlocks() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let existingItem = try documentItemRepository.create(
            DocumentItem(documentId: document.id, contentType: "text", orderKey: OrderKey.between(nil, nil))
        )
        _ = try textItemRepository.create(TextContent(itemId: existingItem.id, textKind: TextItemKind.paragraph, plainText: "Hello"))

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        #expect(viewModel.items.count == 1)
        #expect(viewModel.textContent(forItemId: viewModel.items[0].id).plainText == "Hello")
        #expect(viewModel.focusedBlockId == nil)
    }

    @Test("Editing a block's text updates it in memory immediately and persists it once the debounce settles")
    func updateBlockTextPersistsAfterDebounce() async throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .milliseconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "Today was a good day")

        // In-memory state updates immediately, before the debounced save runs.
        #expect(viewModel.textContent(forItemId: blockId).plainText == "Today was a good day")

        // The database write hasn't happened yet — debounced, not immediate.
        let beforeDebounce = try textItemRepository.find(itemId: blockId)
        #expect(beforeDebounce?.plainText != "Today was a good day")

        try await Task.sleep(for: .milliseconds(50))

        let reloaded = try #require(try textItemRepository.find(itemId: blockId))
        #expect(reloaded.plainText == "Today was a good day")
    }

    @Test("Backgrounding the app flushes a pending debounced edit immediately")
    func flushPendingChangesPersistsImmediately() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "Saved before backgrounding")
        viewModel.flushPendingChanges()

        let reloaded = try #require(try textItemRepository.find(itemId: blockId))
        #expect(reloaded.plainText == "Saved before backgrounding")
    }

    @Test("Pressing Enter splits the block at the cursor and creates a new block below it, focused")
    func insertBlockSplitsAtCursorAndFocusesNewBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)

        let text = "Hello world"
        // Cursor right after "Hello" (offset 5) — "Hello" stays, " world" moves down.
        viewModel.insertBlock(after: firstBlockId, currentText: text, cursorOffset: 5)

        #expect(viewModel.items.count == 2)
        #expect(viewModel.textContent(forItemId: viewModel.items[0].id).plainText == "Hello")
        #expect(viewModel.textContent(forItemId: viewModel.items[1].id).plainText == " world")
        #expect(viewModel.textContent(forItemId: viewModel.items[1].id).textKind == TextItemKind.paragraph)
        #expect(viewModel.focusedBlockId == viewModel.items[1].id)

        let stored = try storedPlainTexts(
            documentId: document.id, documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        #expect(stored == ["Hello", " world"])
    }

    @Test("Pressing Enter at the end of a block creates an empty block below it")
    func insertBlockAtEndCreatesEmptyBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)

        let text = "Hello world"
        viewModel.insertBlock(after: firstBlockId, currentText: text, cursorOffset: text.count)

        #expect(viewModel.items.count == 2)
        #expect(viewModel.textContent(forItemId: viewModel.items[0].id).plainText == "Hello world")
        #expect(viewModel.textContent(forItemId: viewModel.items[1].id).plainText == "")
        #expect(viewModel.focusedBlockId == viewModel.items[1].id)
    }

    @Test(
        "Pressing Enter inside a bulleted/numbered list item continues the list instead of dropping to a paragraph",
        arguments: [TextItemKind.bulletedListItem, TextItemKind.numberedListItem]
    )
    func insertBlockAfterListItemContinuesSameListType(_ textKind: String) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(firstBlockId, text: textKind == TextItemKind.bulletedListItem ? "- First" : "1. First")

        viewModel.insertBlock(after: firstBlockId, currentText: "First", cursorOffset: "First".count)

        #expect(viewModel.items.count == 2)
        let newBlockId = try #require(viewModel.items.last?.id)
        #expect(viewModel.textContent(forItemId: newBlockId).textKind == textKind)
        #expect(viewModel.textContent(forItemId: newBlockId).plainText == "")
        #expect(viewModel.focusedBlockId == newBlockId)
    }

    @Test("Pressing Enter inside a checklist item continues the checklist, always starting the new item unchecked")
    func insertBlockAfterChecklistItemContinuesChecklistUnchecked() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(firstBlockId, text: "- [x] Done already")

        viewModel.insertBlock(after: firstBlockId, currentText: "Done already", cursorOffset: "Done already".count)

        #expect(viewModel.items.count == 2)
        let newBlockId = try #require(viewModel.items.last?.id)
        #expect(viewModel.textContent(forItemId: newBlockId).textKind == TextItemKind.checklist)
        #expect(viewModel.textContent(forItemId: newBlockId).plainText == "")
        // A new checklist item always starts unchecked, even though the
        // item Enter was pressed inside was already checked.
        #expect(viewModel.textContent(forItemId: newBlockId).isChecked == false)
    }

    @Test(
        "Pressing Enter inside a non-list block (heading/quote/code) still creates a plain paragraph below it",
        arguments: [TextItemKind.heading, TextItemKind.quote, TextItemKind.codeBlock]
    )
    func insertBlockAfterNonListBlockStillCreatesParagraph(_ textKind: String) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)
        switch textKind {
        case TextItemKind.heading: viewModel.updateBlockText(firstBlockId, text: "# Title")
        case TextItemKind.quote: viewModel.updateBlockText(firstBlockId, text: "> Quote")
        default: viewModel.updateBlockText(firstBlockId, text: "```swift")
        }

        viewModel.insertBlock(after: firstBlockId, currentText: "Title", cursorOffset: "Title".count)

        let newBlockId = try #require(viewModel.items.last?.id)
        #expect(viewModel.textContent(forItemId: newBlockId).textKind == TextItemKind.paragraph)
    }

    @Test("Pressing Enter on a block that isn't the last inserts the new block between them without touching the later block's orderKey")
    func insertBlockDoesNotDisturbLaterSiblingsOrderKey() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)

        // Add a second block manually so there's something after the split point.
        let secondOrderKey = OrderKey.between(viewModel.items[0].orderKey, nil)
        let secondItem = try documentItemRepository.create(
            DocumentItem(documentId: document.id, contentType: "text", orderKey: secondOrderKey)
        )
        _ = try textItemRepository.create(TextContent(itemId: secondItem.id, textKind: TextItemKind.paragraph, plainText: "Second"))
        viewModel.load()
        #expect(viewModel.items.map(\.id) == [firstBlockId, secondItem.id])

        viewModel.insertBlock(after: firstBlockId, currentText: "First", cursorOffset: 5)

        #expect(viewModel.items.count == 3)
        #expect(viewModel.items.map { viewModel.textContent(forItemId: $0.id).plainText } == ["First", "", "Second"])
        // The un-moved third sibling's orderKey is exactly what it was
        // before the insert — no renumbering, unlike the old integer
        // sortOrder version of this method.
        #expect(viewModel.items[2].orderKey == secondOrderKey)

        let stored = try storedPlainTexts(
            documentId: document.id, documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        #expect(stored == ["First", "", "Second"])
    }

    @Test("Backspace at the start of an empty block deletes it and focuses the previous block at its end")
    func backspaceAtStartOfEmptyBlockDeletesItAndFocusesPreviousBlockEnd() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)

        // Add a second, empty block right below the first.
        let secondOrderKey = OrderKey.between(viewModel.items[0].orderKey, nil)
        let secondItem = try documentItemRepository.create(
            DocumentItem(documentId: document.id, contentType: "text", orderKey: secondOrderKey)
        )
        _ = try textItemRepository.create(TextContent(itemId: secondItem.id, textKind: TextItemKind.paragraph, plainText: ""))
        // A third block follows, to check the list stays contiguous after delete.
        let thirdOrderKey = OrderKey.between(secondOrderKey, nil)
        let thirdItem = try documentItemRepository.create(
            DocumentItem(documentId: document.id, contentType: "text", orderKey: thirdOrderKey)
        )
        _ = try textItemRepository.create(TextContent(itemId: thirdItem.id, textKind: TextItemKind.paragraph, plainText: "Third"))
        viewModel.load()
        viewModel.updateBlockText(firstBlockId, text: "First")

        viewModel.mergeOrDeleteBlock(secondItem.id, currentText: "")

        #expect(viewModel.items.map(\.id) == [firstBlockId, thirdItem.id])
        #expect(viewModel.textContent(forItemId: firstBlockId).plainText == "First")
        #expect(viewModel.focusedBlockId == firstBlockId)
        #expect(viewModel.focusedBlockCursorOffset == "First".utf16.count)

        // The empty block is soft-deleted, not just dropped in memory.
        let stored = try documentItemRepository.children(documentId: document.id, parentItemId: nil)
        #expect(stored.map(\.id) == [firstBlockId, thirdItem.id])

        let deleted = try documentItemRepository.find(id: secondItem.id)
        #expect(deleted?.deletedAt != nil)
    }

    @Test("Backspace at the start of a non-empty block merges its text into the previous block")
    func backspaceAtStartOfNonEmptyBlockMergesIntoPreviousBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(firstBlockId, text: "Hello")
        viewModel.flushPendingChanges()

        let secondOrderKey = OrderKey.between(viewModel.items[0].orderKey, nil)
        let secondItem = try documentItemRepository.create(
            DocumentItem(documentId: document.id, contentType: "text", orderKey: secondOrderKey)
        )
        _ = try textItemRepository.create(TextContent(itemId: secondItem.id, textKind: TextItemKind.paragraph, plainText: " world"))
        viewModel.load()
        #expect(viewModel.items.map(\.id) == [firstBlockId, secondItem.id])

        viewModel.mergeOrDeleteBlock(secondItem.id, currentText: " world")

        #expect(viewModel.items.count == 1)
        #expect(viewModel.items[0].id == firstBlockId)
        #expect(viewModel.textContent(forItemId: firstBlockId).plainText == "Hello world")
        #expect(viewModel.focusedBlockId == firstBlockId)
        // Caret lands at the seam between "Hello" and " world".
        #expect(viewModel.focusedBlockCursorOffset == "Hello".utf16.count)

        let stored = try storedPlainTexts(
            documentId: document.id, documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        #expect(stored == ["Hello world"])

        let deleted = try documentItemRepository.find(id: secondItem.id)
        #expect(deleted?.deletedAt != nil)
    }

    @Test("Backspace at the start of the document's first block does nothing")
    func backspaceAtStartOfFirstBlockDoesNothing() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(firstBlockId, text: "Only block")
        // Clear the focus state `load()`'s bootstrap set, so the assertion
        // below reflects `mergeOrDeleteBlock`'s own behavior rather than a
        // leftover from loading a brand-new document.
        viewModel.focusHandled()

        viewModel.mergeOrDeleteBlock(firstBlockId, currentText: "Only block")

        #expect(viewModel.items.count == 1)
        #expect(viewModel.items[0].id == firstBlockId)
        #expect(viewModel.focusedBlockId == nil)
    }

    @Test("A brand-new document with no content shows the empty-state placeholder")
    func showsEmptyContentPlaceholderForBrandNewDocument() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Untitled"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        #expect(viewModel.showsEmptyContentPlaceholder)
    }

    @Test("Typing into the document's only block hides the empty-state placeholder")
    func hidesEmptyContentPlaceholderOnceTextIsTyped() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Untitled"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(firstBlockId, text: "Hello")

        #expect(!viewModel.showsEmptyContentPlaceholder)
    }

    @Test("A document with more than one block doesn't show the empty-state placeholder")
    func hidesEmptyContentPlaceholderWhenMultipleBlocksExist() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)

        // Splitting the empty block into two via Enter leaves two empty
        // paragraph blocks — no longer the single-empty-block state.
        viewModel.insertBlock(after: firstBlockId, currentText: "", cursorOffset: 0)

        #expect(viewModel.items.count == 2)
        #expect(!viewModel.showsEmptyContentPlaceholder)
    }

    @Test("Loading a document whose only block already has text doesn't show the empty-state placeholder")
    func hidesEmptyContentPlaceholderForExistingNonEmptyBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let existingItem = try documentItemRepository.create(
            DocumentItem(documentId: document.id, contentType: "text", orderKey: OrderKey.between(nil, nil))
        )
        _ = try textItemRepository.create(TextContent(itemId: existingItem.id, textKind: TextItemKind.paragraph, plainText: "Hello"))

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        #expect(!viewModel.showsEmptyContentPlaceholder)
    }

    // MARK: - §15.2 error states

    @Test("A failed block save sets errorMessage to the §15.2 '저장 실패' text")
    func persistBlockFailureSetsSaveErrorMessage() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .milliseconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        // Remove the block's rows out from under the view model, so the
        // next save (`persistBlock`'s `textItemRepository.update`) finds
        // no matching row and throws `RepositoryError.recordNotFound` —
        // simulating a write that fails to persist.
        try documentItemRepository.hardDelete(id: blockId)

        #expect(viewModel.errorMessage == nil)

        // `mergeOrDeleteBlock` on the only block does nothing (PLANNING's
        // "every document keeps ≥1 block" invariant), so use a keyboard
        // shortcut's immediate-persist path instead — toggling bold on an
        // empty block does nothing, so use the structural Heading
        // conversion instead, which also persists immediately.
        viewModel.convertBlockToHeading(blockId, level: 1)

        #expect(viewModel.errorMessage == AppErrorMessages.saveFailed)
    }

    @Test("A failed block delete sets errorMessage to the §15.2 '삭제 실패' text")
    func mergeOrDeleteBlockFailureSetsDeleteErrorMessage() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)

        // Create a second, empty block below the first so Backspace-at-start
        // on it has something to merge/delete into.
        viewModel.insertBlock(after: firstBlockId, currentText: "", cursorOffset: 0)
        let secondBlockId = try #require(viewModel.items.last?.id)

        // Detach the in-memory store from its coordinator so the
        // soft-delete's `context.save()` call throws instead of
        // succeeding — the Core Data equivalent of closing the underlying
        // database connection out from under a pending write.
        try store.simulateStoreFailure()

        #expect(viewModel.errorMessage == nil)

        viewModel.mergeOrDeleteBlock(secondBlockId, currentText: "")

        #expect(viewModel.errorMessage == AppErrorMessages.deleteFailed)
    }

    // MARK: - Back button label (`Planning_6_FolderNavigationFlow` callout ①)

    @Test("A root-level document keeps the existing '< Back' label")
    func loadKeepsExistingBackLabelForRootDocument() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(folderId: nil, title: "Untitled"))
        let viewModel = makeViewModel(document: document, store: store)

        viewModel.load()

        #expect(viewModel.backButtonLabel == .root)
        #expect(viewModel.backButtonText == "< Back")
    }

    @Test("A document filed inside a folder shows that folder's name in the back label")
    func loadResolvesParentFolderNameForDocumentInFolder() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let folderRepository = FolderRepository(context: store.context)

        let folder = try folderRepository.create(Folder(name: "일상"))
        let document = try documentRepository.create(Document(folderId: folder.id, title: "오늘의 일기"))
        let viewModel = makeViewModel(document: document, store: store)

        viewModel.load()

        #expect(viewModel.backButtonLabel == .parentFolder(name: "일상"))
        #expect(viewModel.backButtonText == "< 일상")
    }

    @Test("A document whose folder lookup fails falls back to the root back label")
    func loadFallsBackToRootLabelWhenFolderLookupFails() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        // `folderId` points at a folder that doesn't (or no longer) exists.
        let document = try documentRepository.create(Document(folderId: "missing-folder-id", title: "Orphaned"))
        let viewModel = makeViewModel(document: document, store: store)

        viewModel.load()

        #expect(viewModel.backButtonLabel == .root)
        #expect(viewModel.backButtonText == "< Back")
    }

    @Test("Tapping a block's '잠금' swipe action sets the not-yet-supported notice")
    func lockBlockTappedSetsNotYetSupportedNotice() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "오늘의 일기"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        #expect(viewModel.lockNotice == nil)

        viewModel.lockBlockTapped(blockId)

        // `Planning_9_SwipeActionFlow` callout ⑤ / NO-001 §1.2 — Secret
        // Lock's actual encryption is out of scope, so this only surfaces
        // a short notice rather than locking anything for real.
        #expect(viewModel.lockNotice == AppErrorMessages.secretLockNotYetSupported)
        // The block itself is untouched — no actual lock state exists yet.
        #expect(viewModel.items.first?.id == blockId)
    }
}
