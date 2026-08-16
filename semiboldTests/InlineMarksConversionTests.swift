import Testing

@testable import semibold

/// Tests for `DetailViewModel.updateBlockText`'s inline-mark handling
/// (`markdown-phase4` AC6).
///
/// **NO-005 behavioral deviation (not just a renamed model)**: the
/// pre-NO-005 editor parsed `**bold**`/`*italic*`/`~~strike~~`/`` `code` ``/
/// `[text](url)` out of typed text into `RichTextSpan`s on every keystroke.
/// `DetailViewModel.updateBlockText`'s "Inline marks deviation" doc comment
/// documents that this editor deliberately no longer does that: typed text
/// is stored verbatim (delimiters and all) in `TextContent.plainText`, and
/// any `TextMark`s an item already had are invalidated (dropped) the
/// moment it's next persisted, rather than left pointing at stale offsets
/// the editor has no way to re-derive after a plain-text edit. Inline-mark
/// *parsing* itself (`RichTextSpan.parse`) is unchanged and still covered
/// by `InlineMarksTests`; mark *persistence* is exercised by the NO-005
/// migration tests (`DocumentBlockMigrationPolicy` fans a migrated block's
/// spans out into real `TextMark` rows). This file's job is narrower now:
/// prove `DetailViewModel` actually follows its own documented "keep
/// delimiters literal, invalidate stale marks on edit" contract, rather
/// than re-testing parsing/persistence logic that lives elsewhere.
///
/// Split out from `DetailViewModelTests`/`*ConversionTests`, following the
/// AC3 "per-topic test file" convention.
@MainActor
struct InlineMarksConversionTests {
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

    @Test("Typing '**bold** text' into a paragraph item keeps the delimiters literal and creates no TextMark")
    func boldTextInParagraphStaysLiteral() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "**bold** text")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        // Delimiters stay literal — the plain `UITextView`-backed input
        // round-trips exactly what the user typed rather than the editor
        // fighting it mid-edit.
        #expect(content.plainText == "**bold** text")
        #expect(viewModel.marksByItemId[blockId] == nil)
    }

    @Test("Typing various inline-mark syntax (italic, strike, inline code, link) keeps every delimiter literal")
    func variousInlineMarkSyntaxStaysLiteral() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        let typed = "*italic* and ~~strike~~ and `code` and [link](https://example.com)"
        viewModel.updateBlockText(blockId, text: typed)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText == typed)
        #expect(viewModel.marksByItemId[blockId] == nil)
    }

    @Test("Inline mark syntax composes with heading conversion — '# **bold** title' keeps delimiters literal")
    func inlineMarkSyntaxComposesWithHeadingConversion() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "# **bold** title")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.heading)
        #expect(content.headingLevel == 1)
        #expect(content.plainText == "**bold** title")
    }

    @Test("Typing 'plain' (no Markdown syntax) leaves plainText unchanged and creates no TextMark")
    func plainTextStaysUnmarked() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "plain text")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText == "plain text")
        #expect(viewModel.marksByItemId[blockId] == nil)
    }

    @Test("Editing an item that already has TextMarks (e.g. from a migrated document) clears them once persisted")
    func editingItemWithExistingMarksInvalidatesThem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let textMarkRepository = TextMarkRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let item = try documentItemRepository.create(
            DocumentItem(documentId: document.id, contentType: "text", orderKey: OrderKey.between(nil, nil))
        )
        _ = try textItemRepository.create(
            TextContent(itemId: item.id, textKind: TextItemKind.paragraph, plainText: "bold text")
        )
        // Simulates what a pre-NO-005 migrated document's "**bold** text"
        // would decompose into: a "bold" TextMark over "bold" (offsets 0-4).
        try textMarkRepository.create(TextMark(itemId: item.id, startOffset: 0, endOffset: 4, markType: "bold"))

        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        #expect(viewModel.marksByItemId[item.id]?.isEmpty == false)

        viewModel.updateBlockText(item.id, text: "bold text, revised")

        // A plain-text edit is debounced, but the mark invalidation itself
        // happens inside `persistBlock` regardless of when that runs — call
        // it directly (like `flushPendingChanges` would) so the assertions
        // below don't depend on the debounce timer.
        viewModel.persistBlock(item.id)

        #expect(viewModel.marksByItemId[item.id] == nil)
        #expect(try textMarkRepository.marks(itemId: item.id).isEmpty)
    }
}
