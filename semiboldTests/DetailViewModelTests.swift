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
            listGroupRepository: ListGroupRepository(context: store.context),
            folderRepository: FolderRepository(context: store.context),
            autosaveDebounceInterval: autosaveDebounceInterval
        )
    }

    /// The persisted plain text of `documentId`'s items, in display order
    /// — the "read it back from the database" counterpart to
    /// `viewModel.items.map { viewModel.textContent(forItemId: $0.id)
    /// .plainText }`, used to confirm an edit actually reached storage and
    /// not just the in-memory view model.
    private func storedPlainTexts(
        documentId: String,
        documentItemRepository: DocumentItemRepository,
        textItemRepository: TextItemRepository
    ) throws -> [String] {
        let items = try documentItemRepository.allItems(documentId: documentId)
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
        let stored = try documentItemRepository.allItems(documentId: document.id)
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

    @Test(
        "Pressing Enter on an empty list item exits the list — converts it to a paragraph instead of continuing",
        arguments: [TextItemKind.bulletedListItem, TextItemKind.numberedListItem, TextItemKind.checklist]
    )
    func insertBlockOnEmptyListItemExitsToParagraph(_ textKind: String) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)
        switch textKind {
        case TextItemKind.bulletedListItem: viewModel.updateBlockText(firstBlockId, text: "- ")
        case TextItemKind.numberedListItem: viewModel.updateBlockText(firstBlockId, text: "1. ")
        default: viewModel.updateBlockText(firstBlockId, text: "- [ ] ")
        }
        #expect(viewModel.textContent(forItemId: firstBlockId).textKind == textKind)

        viewModel.insertBlock(after: firstBlockId, currentText: "", cursorOffset: 0)

        // No new block was created — the same block converted in place.
        #expect(viewModel.items.map(\.id) == [firstBlockId])
        #expect(viewModel.textContent(forItemId: firstBlockId).textKind == TextItemKind.paragraph)
        #expect(viewModel.textContent(forItemId: firstBlockId).plainText == "")
        // Immediately, without a reload — `DetailScreen`'s
        // `.onChange(of: viewModel.items)` re-derives the on-screen
        // keyboard toolbar from exactly this, so a block that just exited
        // a list must stop reporting list-nesting info right away.
        #expect(viewModel.listNestingInfo(forItemId: firstBlockId) == nil)
    }

    @Test("Typing '---' converts a paragraph to a divider and drops keyboard focus")
    func typingTripleDashConvertsToDividerAndDefocuses() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "---")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.divider)
        #expect(content.plainText == "---")
        // A divider has nothing left to type — focus drops immediately
        // instead of staying in text-edit mode.
        #expect(viewModel.blockIdToDefocus == blockId)

        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.divider)
    }

    @Test("'--' (two dashes) doesn't trigger divider conversion")
    func doubleDashDoesNotConvertToDivider() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "--")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "--")
        #expect(viewModel.blockIdToDefocus == nil)
    }

    @Test("Picking Divider from the Slash Command sheet drops keyboard focus")
    func convertBlockToDividerDropsKeyboardFocus() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.convertBlock(blockId, toSlashCommandOption: .divider)

        #expect(viewModel.textContent(forItemId: blockId).textKind == TextItemKind.divider)
        #expect(viewModel.blockIdToDefocus == blockId)
    }

    // MARK: - `dismissKeyboard(forBlockId:)` (`05-onscreen-keyboard-indent-toolbar`)

    @Test("dismissKeyboard(forBlockId:) sets blockIdToDefocus to the given block, the same signal the divider flow uses")
    func dismissKeyboardSetsBlockIdToDefocus() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        #expect(viewModel.blockIdToDefocus == nil)

        viewModel.dismissKeyboard(forBlockId: blockId)

        #expect(viewModel.blockIdToDefocus == blockId)

        // `defocusHandled()` (already called by `DetailScreen`'s
        // `.onChange(of: viewModel.blockIdToDefocus)` handler) clears it
        // back to `nil`, the same way it does for the divider-defocus flow.
        viewModel.defocusHandled()
        #expect(viewModel.blockIdToDefocus == nil)
    }

    @Test("Editing a divider's literal '---' text keeps it a divider")
    func editingDividerTextUnchangedStaysDivider() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.convertBlock(blockId, toSlashCommandOption: .divider)

        viewModel.updateBlockText(blockId, text: "---")

        #expect(viewModel.textContent(forItemId: blockId).textKind == TextItemKind.divider)
        #expect(viewModel.textContent(forItemId: blockId).plainText == "---")
    }

    @Test("Editing a divider's text away from '---' converts it to a plain paragraph")
    func editingDividerTextAwayFromRuleConvertsToParagraph() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.convertBlock(blockId, toSlashCommandOption: .divider)

        viewModel.updateBlockText(blockId, text: "-- Notes")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "-- Notes")

        // A type change is a structural edit — persisted immediately.
        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.paragraph)
        #expect(stored.plainText == "-- Notes")
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
        let stored = try documentItemRepository.allItems(documentId: document.id)
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

    @Test(
        "Backspace on an empty list item exits the list — converts it to a paragraph instead of deleting/merging",
        arguments: [TextItemKind.bulletedListItem, TextItemKind.numberedListItem, TextItemKind.checklist]
    )
    func mergeOrDeleteBlockOnEmptyListItemExitsToParagraph(_ textKind: String) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)

        // Add a second, empty list item right below the first — this
        // exercises the non-first-block path too (the first-block path is
        // covered by `backspaceAtStartOfFirstBlockDoesNothing`'s sibling
        // below).
        let secondOrderKey = OrderKey.between(viewModel.items[0].orderKey, nil)
        let secondItem = try documentItemRepository.create(
            DocumentItem(documentId: document.id, contentType: "text", orderKey: secondOrderKey)
        )
        let isChecked = textKind == TextItemKind.checklist ? false : nil
        _ = try textItemRepository.create(
            TextContent(itemId: secondItem.id, textKind: textKind, plainText: "", isChecked: isChecked)
        )
        // Reload to pick up the second block *before* editing the first
        // one — editing goes through the debounced save path, so doing it
        // before this reload would have the reload's fresh-from-DB read
        // stomp the in-memory-only edit right back to empty.
        viewModel.load()
        viewModel.updateBlockText(firstBlockId, text: "First")

        viewModel.mergeOrDeleteBlock(secondItem.id, currentText: "")

        // No block was deleted or merged — the second block converted in
        // place, and the first block's text is untouched.
        #expect(viewModel.items.map(\.id) == [firstBlockId, secondItem.id])
        #expect(viewModel.textContent(forItemId: firstBlockId).plainText == "First")
        #expect(viewModel.textContent(forItemId: secondItem.id).textKind == TextItemKind.paragraph)
        #expect(viewModel.textContent(forItemId: secondItem.id).plainText == "")
        // Immediately, without a reload — same rationale as
        // `insertBlockOnEmptyListItemExitsToParagraph`'s equivalent check.
        #expect(viewModel.listNestingInfo(forItemId: secondItem.id) == nil)

        let stored = try documentItemRepository.find(id: secondItem.id)
        #expect(stored?.deletedAt == nil)
    }

    @Test(
        "Backspace on an empty list item that's also the document's first block still exits to a paragraph",
        arguments: [TextItemKind.bulletedListItem, TextItemKind.numberedListItem, TextItemKind.checklist]
    )
    func mergeOrDeleteBlockOnEmptyFirstListItemExitsToParagraph(_ textKind: String) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)
        switch textKind {
        case TextItemKind.bulletedListItem: viewModel.updateBlockText(firstBlockId, text: "- ")
        case TextItemKind.numberedListItem: viewModel.updateBlockText(firstBlockId, text: "1. ")
        default: viewModel.updateBlockText(firstBlockId, text: "- [ ] ")
        }

        viewModel.mergeOrDeleteBlock(firstBlockId, currentText: "")

        #expect(viewModel.items.map(\.id) == [firstBlockId])
        #expect(viewModel.textContent(forItemId: firstBlockId).textKind == TextItemKind.paragraph)
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

    @Test("A root-level document shows the house icon back button")
    func loadShowsHouseIconForRootDocument() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(folderId: nil, title: "Untitled"))
        let viewModel = makeViewModel(document: document, store: store)

        viewModel.load()

        #expect(viewModel.backButtonLabel == .root)
        #expect(viewModel.backButtonLabel.iconName == "house.fill")
    }

    @Test("A document filed inside a folder shows the chevron icon, naming that folder only for accessibility")
    func loadResolvesParentFolderNameForDocumentInFolder() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let folderRepository = FolderRepository(context: store.context)

        let folder = try folderRepository.create(Folder(name: "일상"))
        let document = try documentRepository.create(Document(folderId: folder.id, title: "오늘의 일기"))
        let viewModel = makeViewModel(document: document, store: store)

        viewModel.load()

        #expect(viewModel.backButtonLabel == .parentFolder(name: "일상"))
        #expect(viewModel.backButtonLabel.iconName == "chevron.left")
        #expect(viewModel.backButtonLabel.accessibilityLabel == "뒤로가기, 일상")
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
        #expect(viewModel.backButtonLabel.iconName == "house.fill")
    }

    // MARK: - `indentBlock`/`outdentBlock` (`tasks/NO-009.md` §2.1/§3.1)

    /// Creates a `DocumentItem` + its `TextContent` directly through the
    /// repositories (bypassing `DetailViewModel`'s Markdown-prefix
    /// conversion), so a test can set up already-nested items — specific
    /// `depth`/`listGroupId`/`orderKey` values — before exercising
    /// `indentBlock`/`outdentBlock`/`numberedListNumber` against them.
    @discardableResult
    private func createItem(
        documentId: String,
        depth: Int = 0,
        listGroupId: String? = nil,
        orderKey: String,
        textKind: String,
        text: String,
        documentItemRepository: DocumentItemRepository,
        textItemRepository: TextItemRepository
    ) throws -> DocumentItem {
        let item = try documentItemRepository.create(
            DocumentItem(
                documentId: documentId, depth: depth, listGroupId: listGroupId, contentType: "text", orderKey: orderKey
            )
        )
        _ = try textItemRepository.create(TextContent(itemId: item.id, textKind: textKind, plainText: text))
        return item
    }

    @Test("Indenting a list item with no previous sibling does nothing")
    func indentBlockNoOpsWithNoPreviousSibling() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(firstBlockId, text: "- Only item")
        #expect(viewModel.textContent(forItemId: firstBlockId).textKind == TextItemKind.bulletedListItem)

        viewModel.indentBlock(firstBlockId)

        #expect(viewModel.items.count == 1)
        #expect(viewModel.items[0].depth == 0)
    }

    @Test("Indenting with a different-kind previous sibling does nothing")
    func indentBlockNoOpsWithDifferentKindPreviousSibling() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let bulletedItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.bulletedListItem,
            text: "Bulleted", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let numberedItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(bulletedItem.orderKey, nil), textKind: TextItemKind.numberedListItem,
            text: "Numbered", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        #expect(viewModel.items.map(\.id) == [bulletedItem.id, numberedItem.id])

        viewModel.indentBlock(numberedItem.id)

        #expect(viewModel.items.map(\.id) == [bulletedItem.id, numberedItem.id])
        #expect(viewModel.items.first(where: { $0.id == numberedItem.id })?.depth == 0)
    }

    @Test("Indenting with a same-kind previous sibling nests it under that sibling, in place")
    func indentBlockWithSameKindPreviousSiblingSucceeds() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let firstItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.bulletedListItem,
            text: "First", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let secondItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(firstItem.orderKey, nil), textKind: TextItemKind.bulletedListItem,
            text: "Second", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.indentBlock(secondItem.id)

        // The item stays right where it was in display order — indenting
        // only changes its `depth`, not its position or `orderKey`.
        #expect(viewModel.items.map(\.id) == [firstItem.id, secondItem.id])
        #expect(viewModel.items[1].depth == 1)
        #expect(viewModel.items[1].orderKey == secondItem.orderKey)
        #expect(viewModel.depth(forItemId: secondItem.id) == 1)
        #expect(viewModel.depth(forItemId: firstItem.id) == 0)

        // Persisted immediately, not just in memory.
        let stored = try #require(try documentItemRepository.find(id: secondItem.id))
        #expect(stored.depth == 1)
    }

    @Test("Outdenting a top-level item does nothing")
    func outdentBlockNoOpsOnTopLevelItem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstBlockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(firstBlockId, text: "- Only item")

        viewModel.outdentBlock(firstBlockId)

        #expect(viewModel.items.count == 1)
        #expect(viewModel.items[0].depth == 0)
    }

    @Test("Outdenting a nested item promotes it to top-level, right after its former parent's subtree")
    func outdentBlockPromotesNestedItemAfterFormerParent() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let listGroup = try ListGroupRepository(context: store.context).create(
            ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem)
        )
        let parentItem = try createItem(
            documentId: document.id, listGroupId: listGroup.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem,
            text: "Parent", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let nestedItem = try createItem(
            documentId: document.id, depth: 1, listGroupId: listGroup.id,
            orderKey: OrderKey.between(parentItem.orderKey, nil), textKind: TextItemKind.bulletedListItem,
            text: "Nested", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let thirdItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nestedItem.orderKey, nil), textKind: TextItemKind.bulletedListItem,
            text: "Third", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        #expect(viewModel.items.map(\.id) == [parentItem.id, nestedItem.id, thirdItem.id])

        viewModel.outdentBlock(nestedItem.id)

        #expect(viewModel.items.map(\.id) == [parentItem.id, nestedItem.id, thirdItem.id])
        let promoted = try #require(viewModel.items.first(where: { $0.id == nestedItem.id }))
        #expect(promoted.depth == 0)
        #expect(viewModel.depth(forItemId: nestedItem.id) == 0)
        // Positioned between the former parent and whatever followed it.
        #expect(promoted.orderKey > parentItem.orderKey)
        #expect(promoted.orderKey < thirdItem.orderKey)

        let stored = try #require(try documentItemRepository.find(id: nestedItem.id))
        #expect(stored.depth == 0)
    }

    @Test("indent, indent, outdent, outdent round-trips back to the original flat, top-level layout")
    func indentIndentOutdentOutdentRoundTripRestoresOriginalPosition() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let itemA = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.bulletedListItem,
            text: "A", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemB = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemA.orderKey, nil), textKind: TextItemKind.bulletedListItem,
            text: "B", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemC = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemB.orderKey, nil), textKind: TextItemKind.bulletedListItem,
            text: "C", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        #expect(viewModel.items.map(\.id) == [itemA.id, itemB.id, itemC.id])

        viewModel.indentBlock(itemC.id) // C nests under B.
        viewModel.indentBlock(itemB.id) // B nests under A, carrying C (still B's child) along with it.

        #expect(viewModel.items.map(\.id) == [itemA.id, itemB.id, itemC.id])
        #expect(viewModel.depth(forItemId: itemA.id) == 0)
        #expect(viewModel.depth(forItemId: itemB.id) == 1)
        #expect(viewModel.depth(forItemId: itemC.id) == 2)

        viewModel.outdentBlock(itemB.id) // B promoted back to top-level; C stays B's child.
        viewModel.outdentBlock(itemC.id) // C promoted back to top-level.

        #expect(viewModel.items.map(\.id) == [itemA.id, itemB.id, itemC.id])
        #expect(viewModel.items.allSatisfy { $0.depth == 0 })
        #expect(viewModel.depth(forItemId: itemA.id) == 0)
        #expect(viewModel.depth(forItemId: itemB.id) == 0)
        #expect(viewModel.depth(forItemId: itemC.id) == 0)
    }

    @Test("numberedListNumber counts each same-depth group independently")
    func numberedListNumberCountsSiblingsUnderSameParentOnly() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let listGroup = try ListGroupRepository(context: store.context).create(
            ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem)
        )
        let container = try createItem(
            documentId: document.id, listGroupId: listGroup.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem,
            text: "Container", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let nestedFirst = try createItem(
            documentId: document.id, depth: 1, listGroupId: listGroup.id, orderKey: OrderKey.between(container.orderKey, nil),
            textKind: TextItemKind.numberedListItem,
            text: "Nested 1", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let nestedSecond = try createItem(
            documentId: document.id, depth: 1, listGroupId: listGroup.id, orderKey: OrderKey.between(nestedFirst.orderKey, nil),
            textKind: TextItemKind.numberedListItem,
            text: "Nested 2", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let topLevelFirst = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nestedSecond.orderKey, nil), textKind: TextItemKind.numberedListItem,
            text: "Top 1", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let topLevelSecond = try createItem(
            documentId: document.id, orderKey: OrderKey.between(topLevelFirst.orderKey, nil), textKind: TextItemKind.numberedListItem,
            text: "Top 2", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        #expect(
            viewModel.items.map(\.id) == [container.id, nestedFirst.id, nestedSecond.id, topLevelFirst.id, topLevelSecond.id]
        )

        #expect(viewModel.numberedListNumber(forItemId: nestedFirst.id) == 1)
        #expect(viewModel.numberedListNumber(forItemId: nestedSecond.id) == 2)
        // The top-level group starts fresh at 1 instead of continuing the
        // nested group's count, since it doesn't share `nestedSecond`'s
        // parent.
        #expect(viewModel.numberedListNumber(forItemId: topLevelFirst.id) == 1)
        #expect(viewModel.numberedListNumber(forItemId: topLevelSecond.id) == 2)
    }

    /// Depth is a stored value now, not derived from a parent chain
    /// (`tasks/NO-009.md` §3.1) — indenting an item that already has its
    /// own nested descendants has to explicitly bump their `depth` too,
    /// or their nesting level would silently fall out of sync with what
    /// they render under.
    @Test("Indenting an item with its own descendants carries their depth along with it")
    func indentBlockCascadesDepthToOwnDescendants() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let listGroup = try ListGroupRepository(context: store.context).create(
            ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem)
        )
        let itemA = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.bulletedListItem,
            text: "A", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemB = try createItem(
            documentId: document.id, listGroupId: listGroup.id, orderKey: OrderKey.between(itemA.orderKey, nil),
            textKind: TextItemKind.bulletedListItem,
            text: "B", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemC = try createItem(
            documentId: document.id, depth: 1, listGroupId: listGroup.id, orderKey: OrderKey.between(itemB.orderKey, nil),
            textKind: TextItemKind.bulletedListItem,
            text: "C, already nested under B", documentItemRepository: documentItemRepository,
            textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        #expect(viewModel.depth(forItemId: itemC.id) == 1)

        viewModel.indentBlock(itemB.id) // B nests under A; C should move deeper with it.

        #expect(viewModel.depth(forItemId: itemB.id) == 1)
        #expect(viewModel.depth(forItemId: itemC.id) == 2)
        let storedC = try #require(try documentItemRepository.find(id: itemC.id))
        #expect(storedC.depth == 2)
    }

    @Test("Outdenting an item with its own descendants carries their depth along with it")
    func outdentBlockCascadesDepthToOwnDescendants() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let listGroup = try ListGroupRepository(context: store.context).create(
            ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem)
        )
        let itemA = try createItem(
            documentId: document.id, listGroupId: listGroup.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem,
            text: "A", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemB = try createItem(
            documentId: document.id, depth: 1, listGroupId: listGroup.id, orderKey: OrderKey.between(itemA.orderKey, nil),
            textKind: TextItemKind.bulletedListItem,
            text: "B, nested under A", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemC = try createItem(
            documentId: document.id, depth: 2, listGroupId: listGroup.id, orderKey: OrderKey.between(itemB.orderKey, nil),
            textKind: TextItemKind.bulletedListItem,
            text: "C, nested under B", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        #expect(viewModel.depth(forItemId: itemC.id) == 2)

        viewModel.outdentBlock(itemB.id) // B promotes to top-level; C should move shallower with it.

        #expect(viewModel.items.map(\.id) == [itemA.id, itemB.id, itemC.id])
        #expect(viewModel.depth(forItemId: itemB.id) == 0)
        #expect(viewModel.depth(forItemId: itemC.id) == 1)
        let storedC = try #require(try documentItemRepository.find(id: itemC.id))
        #expect(storedC.depth == 1)
    }

}
