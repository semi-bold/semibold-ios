import Testing

@testable import semibold

/// Tests for `DetailViewModel.updateBlockText`'s heading conversion
/// (`markdown-phase4` AC1): typing `# `/`## `/`### ` converts a paragraph
/// item's `TextContent` to `TextItemKind.heading` at the matching level.
///
/// **NO-005 model note**: rewritten against the `DocumentItem`/
/// `TextContent` model (`tasks/NO-005.md` §3) that replaced
/// `DocumentBlock`/`BlockContent` — same typed-input/assertions as before,
/// translated to the new schema's vocabulary (`TextItemKind`, `plainText`,
/// `headingLevel`). There's no `TextContent.markdownSource`/`contentJSON`
/// equivalent to check literal Markdown round-tripping against — that
/// concern now lives entirely in `MarkdownExporter`
/// (`MarkdownExporterTests`, a separate session's scope), so this only
/// asserts the in-memory/persisted `TextContent` shape.
///
/// Split out from `DetailViewModelTests` (which covers the rest of
/// `DetailViewModel`'s editing/reorder behavior) to keep each suite's body
/// within SwiftLint's `type_body_length`.
@MainActor
struct HeadingConversionTests {
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

    @Test(
        "Typing '# ', '## ', '### ' converts the item to a heading of the matching level, saved immediately",
        arguments: [
            (prefix: "# ", level: 1),
            (prefix: "## ", level: 2),
            (prefix: "### ", level: 3)
        ]
    )
    func typingHeadingPrefixConvertsBlockToHeading(_ testCase: (prefix: String, level: Int)) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        // A long debounce makes sure the heading conversion below is
        // persisted immediately, not via the debounced path.
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: testCase.prefix + "Title")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.heading)
        #expect(content.plainText == "Title")
        #expect(content.headingLevel == testCase.level)

        // Type conversion is a structural change — persisted immediately,
        // not waiting for the (long) debounce interval above.
        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.heading)
        #expect(stored.plainText == "Title")
        #expect(stored.headingLevel == testCase.level)
    }

    @Test("Editing a heading item's text keeps its level and updates plainText")
    func editingHeadingBlockKeepsLevelAndPrefix() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .milliseconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "## Heading")
        // Continue typing in the now-heading item — the displayed text
        // (no '#') is what `ParagraphTextField` reports back.
        viewModel.updateBlockText(blockId, text: "Heading 2")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.heading)
        #expect(content.plainText == "Heading 2")
        #expect(content.headingLevel == 2)
    }

    @Test("A 4th '#' doesn't trigger heading conversion")
    func fourHashesDoesNotConvert() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "#### Title")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "#### Title")
    }

    @Test("A '#' without a trailing space doesn't trigger heading conversion")
    func hashWithoutSpaceDoesNotConvert() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "#hashtag")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "#hashtag")
    }
}
