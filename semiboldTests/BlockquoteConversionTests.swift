import Testing

@testable import semibold

/// Tests for `DetailViewModel.updateBlockText`'s blockquote conversion
/// (`markdown-phase4` AC4): typing `> ` converts a paragraph item to
/// `TextItemKind.quote`, persisted immediately.
///
/// **NO-005 model note**: rewritten against the `DocumentItem`/
/// `TextContent` model (`tasks/NO-005.md` §3). `TextItemKind.quote` is
/// `"quote"`, not `"blockquote"` — `DocumentBlockMigrationPolicy` renamed
/// it to match `DOCUMENT_MODEL.md` §4.1's recommended vocabulary; the
/// conversion trigger (`> `) and behavior are otherwise unchanged.
///
/// Split out from `DetailViewModelTests` (which covers the rest of
/// `DetailViewModel`'s editing/reorder behavior) to keep each suite's body
/// within SwiftLint's `type_body_length`, following AC3's
/// `ChecklistConversionTests` precedent.
@MainActor
struct BlockquoteConversionTests {
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

    @Test("Typing '> quote' converts the item to a blockquote, saved immediately")
    func typingBlockquotePrefixConvertsBlockToBlockquote() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        // A long debounce makes sure the blockquote conversion below is
        // persisted immediately, not via the debounced path.
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "> Quote")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.quote)
        #expect(content.plainText == "Quote")

        // Type conversion is a structural change — persisted immediately,
        // not waiting for the (long) debounce interval above.
        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.quote)
        #expect(stored.plainText == "Quote")
    }

    @Test("Editing a blockquote keeps it a blockquote and updates plainText")
    func editingBlockquoteRebuildsMarkdownSource() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .milliseconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "> Quote")
        // Continue typing in the now-blockquote item — the displayed text
        // (no '> ') is what `ParagraphTextField` reports back.
        viewModel.updateBlockText(blockId, text: "Quote, revised")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.quote)
        #expect(content.plainText == "Quote, revised")
    }

    @Test("'>quote' (no space) does NOT convert to a blockquote")
    func noSpaceAfterAngleBracketDoesNotConvert() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: ">quote")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == ">quote")
    }

    @Test("'>> quote' (second character isn't a space) does NOT convert to a blockquote")
    func doubleAngleBracketDoesNotConvert() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: ">> quote")

        let content = viewModel.textContent(forItemId: blockId)
        // ">> quote" doesn't match "> " (its 2nd character is ">", not a
        // space), so it stays a plain paragraph — same precedent as AC2's
        // "-- item" not matching "- ".
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == ">> quote")
    }

    @Test("'> ' blockquote prefix doesn't conflict with heading/list/checklist prefixes")
    func blockquotePrefixDoesNotConflictWithOtherPrefixes() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))

        for typedText in ["# Title", "- item", "1. item", "- [ ] task"] {
            let item = try documentItemRepository.create(
                DocumentItem(documentId: document.id, contentType: "text", orderKey: OrderKey.between(nil, nil))
            )
            _ = try textItemRepository.create(
                TextContent(itemId: item.id, textKind: TextItemKind.paragraph, plainText: "")
            )
            let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
            viewModel.load()

            viewModel.updateBlockText(item.id, text: typedText)

            let converted = viewModel.textContent(forItemId: item.id)
            #expect(converted.textKind != TextItemKind.quote)
        }
    }
}
