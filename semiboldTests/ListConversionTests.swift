import Testing

@testable import semibold

/// Tests for `DetailViewModel.updateBlockText`'s list conversion
/// (`markdown-phase4` AC2): typing `- ` converts a paragraph item to
/// `TextItemKind.bulletedListItem`, and `<n>. ` converts it to
/// `.numberedListItem`.
///
/// **NO-005 model note**: rewritten against the `DocumentItem`/
/// `TextContent` model (`tasks/NO-005.md` §3). One behavior is genuinely
/// different, not just renamed: the pre-NO-005 model kept whatever literal
/// number the user typed (`DocumentBlock.numberedListNumber`, read back
/// from `markdownSource`); `TextContent` has no field for that (see
/// `DetailViewModel.numberedListNumber(forItemId:)`'s doc comment), so
/// numbering is now computed from an item's position within a run of
/// sibling `numbered_list_item`s. Tests that exercised the old "keeps the
/// typed number" behavior are adapted below to assert the new
/// position-based numbering instead, flagged explicitly at each site
/// rather than silently dropped.
///
/// Split out from `DetailViewModelTests` (which covers the rest of
/// `DetailViewModel`'s editing/reorder behavior) to keep each suite's body
/// within SwiftLint's `type_body_length`.
@MainActor
struct ListConversionTests {
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

    @Test("Typing '- item' converts the item to a bulleted list item, saved immediately")
    func typingHyphenSpacePrefixConvertsBlockToBulletedListItem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        // A long debounce makes sure the list conversion below is
        // persisted immediately, not via the debounced path.
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "- Milk")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.bulletedListItem)
        #expect(content.plainText == "Milk")

        // Type conversion is a structural change — persisted immediately,
        // not waiting for the (long) debounce interval above.
        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.bulletedListItem)
        #expect(stored.plainText == "Milk")
    }

    @Test("Typing '* item' converts the item to a bulleted list item, saved immediately")
    func typingAsteriskSpacePrefixConvertsBlockToBulletedListItem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "* Milk")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.bulletedListItem)
        #expect(content.plainText == "Milk")

        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.bulletedListItem)
        #expect(stored.plainText == "Milk")
    }

    @Test("'*item' without a space doesn't trigger bulleted list conversion")
    func asteriskWithoutSpaceDoesNotConvertToBulletedList() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "*item")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "*item")
    }

    @Test("Typing '1. item' converts the item to a numbered list item, saved immediately")
    func typingNumberDotSpacePrefixConvertsBlockToNumberedListItem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "1. First step")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.numberedListItem)
        #expect(content.plainText == "First step")
        // The lone item in a run of numbered-list siblings is always "1"
        // under the new position-based numbering.
        #expect(viewModel.numberedListNumber(forItemId: blockId) == 1)

        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.numberedListItem)
        #expect(stored.plainText == "First step")
    }

    @Test(
        """
        A multi-digit numbered list prefix is still stripped correctly, but (NO-005 deviation) the literal \
        typed number is no longer kept — numbering is now computed from sibling position
        """
    )
    func multiDigitNumberedListPrefixKeepsLiteralNumber() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "42. Answer")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.numberedListItem)
        #expect(content.plainText == "Answer")
        // NO-005 deviation (documented on `numberedListNumber(forItemId:)`):
        // the typed "42" prefix isn't persisted anywhere in `TextContent` —
        // the sole item in the list is always displayed as "1".
        #expect(viewModel.numberedListNumber(forItemId: blockId) == 1)
    }

    @Test("Sequential numbered-list siblings are numbered by position, not by their originally-typed prefix")
    func sequentialNumberedListItemsAreNumberedByPosition() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let firstId = try #require(viewModel.items.first?.id)

        // Type a literal "5." prefix on the first item and "9." on a
        // second, freshly split item — position-based numbering ignores
        // both literal numbers and numbers them 1, 2 in display order.
        viewModel.updateBlockText(firstId, text: "5. First")
        // The prefix is already consumed — "First" is what the editor
        // displays/reports back for the split below.
        viewModel.insertBlock(after: firstId, currentText: "First", cursorOffset: "First".count)
        let secondId = try #require(viewModel.items.last?.id)
        viewModel.updateBlockText(secondId, text: "9. Second")

        #expect(viewModel.numberedListNumber(forItemId: firstId) == 1)
        #expect(viewModel.numberedListNumber(forItemId: secondId) == 2)
    }

    @Test("Editing a bulleted list item keeps its type and updates plainText")
    func editingBulletedListItemKeepsTypeAndPrefix() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .milliseconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "- Milk")
        // Continue typing in the now-list-item block — the displayed text
        // (no '- ') is what `ParagraphTextField` reports back.
        viewModel.updateBlockText(blockId, text: "Milk and eggs")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.bulletedListItem)
        #expect(content.plainText == "Milk and eggs")
    }

    @Test("Editing a numbered list item keeps its type and updates plainText")
    func editingNumberedListItemKeepsNumberAndPrefix() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .milliseconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "2. Step two")
        viewModel.updateBlockText(blockId, text: "Step two, revised")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.numberedListItem)
        #expect(content.plainText == "Step two, revised")
        // NO-005 deviation: no literal number is retained — the sole item
        // is always "1" under position-based numbering.
        #expect(viewModel.numberedListNumber(forItemId: blockId) == 1)
    }

    @Test("'-item' without a space doesn't trigger bulleted list conversion")
    func hyphenWithoutSpaceDoesNotConvertToBulletedList() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "-item")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "-item")
    }

    @Test("'-- item' doesn't trigger bulleted list conversion")
    func doubleHyphenDoesNotConvertToBulletedList() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "-- item")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "-- item")
    }

    @Test("A digit without '. ' doesn't trigger numbered list conversion")
    func digitWithoutDotSpaceDoesNotConvertToNumberedList() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "1 item")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "1 item")
    }

    @Test("'1.item' without a space after the period doesn't trigger numbered list conversion")
    func digitDotWithoutSpaceDoesNotConvertToNumberedList() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "1.item")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "1.item")
    }
}
