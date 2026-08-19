import Testing

@testable import semibold

/// Tests for `DetailViewModel.updateBlockText`'s code-block conversion
/// (`markdown-phase4` AC5): typing a ` ``` `/` ```<lang> ` fence converts a
/// paragraph item to `TextItemKind.codeBlock`, persisted immediately.
///
/// **NO-005 model note**: rewritten against the `DocumentItem`/
/// `TextContent` model (`tasks/NO-005.md` §3). One behavior is genuinely
/// different, not just renamed: the fence's language identifier (e.g.
/// `"swift"` in ` ```swift `) has no field to live in on `TextContent` —
/// `DOCUMENT_MODEL.md` §4.1's `text_items` columns don't include one (see
/// `DetailViewModel.updateBlockText`'s doc comment) — so it's still
/// detected (to trigger the conversion and to correctly strip the prefix
/// off any trailing code on the same line) but never persisted anywhere.
/// Assertions that would have checked a stored language are dropped here,
/// flagged explicitly rather than silently kept as passing no-ops.
///
/// Split out from `DetailViewModelTests` (which covers the rest of
/// `DetailViewModel`'s editing/reorder behavior) to keep each suite's body
/// within SwiftLint's `type_body_length`, following AC3/AC4's
/// `ChecklistConversionTests`/`BlockquoteConversionTests` precedent.
@MainActor
struct CodeBlockConversionTests {
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

    @Test("Typing '```swift' converts the item to an empty code block, saved immediately")
    func typingFenceWithLanguageConvertsBlockToCodeBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        // A long debounce makes sure the code-block conversion below is
        // persisted immediately, not via the debounced path.
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "```swift")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.codeBlock)
        #expect(content.plainText == "")

        // Type conversion is a structural change — persisted immediately,
        // not waiting for the (long) debounce interval above.
        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.codeBlock)
        #expect(stored.plainText == "")
    }

    @Test("Typing '```' alone converts the item to a code block with no language")
    func typingBareFenceConvertsBlockToCodeBlockWithNoLanguage() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "```")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.codeBlock)
        #expect(content.plainText == "")
    }

    @Test("Typing '```swift let x = 1' keeps 'let x = 1' as the code block's initial code")
    func typingFenceWithTrailingTextKeepsItAsInitialCode() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "```swift let x = 1")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.codeBlock)
        #expect(content.plainText == "let x = 1")
    }

    @Test("Editing a code block keeps it a code block and updates plainText")
    func editingCodeBlockRebuildsMarkdownSource() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .milliseconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "```swift")
        // Continue typing in the now-code-block — the displayed text
        // (after the fence) is what `ParagraphTextField` reports back.
        viewModel.updateBlockText(blockId, text: "let x = 1")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.codeBlock)
        #expect(content.plainText == "let x = 1")
    }

    @Test("'``' (two backticks) does NOT convert to a code block")
    func twoBackticksDoesNotConvert() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "``")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "``")
    }

    @Test("'`' (one backtick) does NOT convert to a code block")
    func oneBacktickDoesNotConvert() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "`")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "`")
    }

    @Test("'```' code-fence prefix doesn't conflict with heading/list/checklist/blockquote prefixes")
    func codeFencePrefixDoesNotConflictWithOtherPrefixes() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))

        for typedText in ["# Title", "- item", "1. item", "- [ ] task", "> quote"] {
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
            #expect(converted.textKind != TextItemKind.codeBlock)
        }
    }
}
