import Testing

@testable import semibold

/// Tests for `DetailViewModel+KeyboardShortcuts` — the view-model side of
/// macOS keyboard shortcuts (`tasks/NO-001.md` §13.2):
///
/// - Cmd+Option+1/2/3 → `convertBlockToHeading(_:level:)`
/// - Cmd+B / Cmd+I    → `toggleBoldOnBlock`/`toggleItalicOnBlock`
/// - Cmd+K            → `toggleLinkOnBlock`
///
/// **NO-005 model note**: rewritten against the `DocumentItem`/
/// `TextContent` model (`tasks/NO-005.md` §3). These shortcuts wrap/unwrap
/// Markdown delimiters directly in `TextContent.plainText` — same as
/// before — rather than recording a `TextMark`
/// (`DetailViewModel+KeyboardShortcuts.swift`'s "NO-005 note"), so the
/// old `contentJSON`-based "marks":["bold"] assertions have no equivalent
/// to check here; `plainText`'s wrapped/unwrapped shape is the complete
/// picture in the new model.
///
/// Split out from `DetailViewModelTests` following the
/// `HeadingConversionTests`/`ChecklistConversionTests` precedent — keeps
/// each suite's body within SwiftLint's `type_body_length`.
@MainActor
struct KeyboardShortcutConversionTests {
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

    // MARK: - Cmd+Option+1/2/3 (Heading conversion)

    @Test(
        "Cmd+Option+1/2/3 converts the focused item to a heading at the matching level, saved immediately",
        arguments: [1, 2, 3]
    )
    func convertBlockToHeadingSetsLevelAndPersists(_ level: Int) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "Diary Entry")

        viewModel.convertBlockToHeading(blockId, level: level)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.heading)
        #expect(content.plainText == "Diary Entry")
        #expect(content.headingLevel == level)

        // Structural change — persisted immediately.
        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.heading)
        #expect(stored.headingLevel == level)
    }

    @Test("Cmd+Option+2 on an already-heading item re-levels it, keeping its text")
    func convertHeadingToDifferentLevelKeepsText() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "# Title")

        viewModel.convertBlockToHeading(blockId, level: 2)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.headingLevel == 2)
        #expect(content.plainText == "Title")
    }

    // MARK: - Cmd+B (Bold)

    @Test("Cmd+B wraps the focused item's whole text in '**…**'")
    func toggleBoldWrapsWholeText() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "Important")

        viewModel.toggleBoldOnBlock(blockId)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText == "**Important**")
    }

    @Test("Cmd+B a second time unwraps '**…**' back to plain text")
    func toggleBoldTwiceUnwraps() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "Important")

        viewModel.toggleBoldOnBlock(blockId)
        viewModel.toggleBoldOnBlock(blockId)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText == "Important")
    }

    @Test("Cmd+B on an empty item does nothing")
    func toggleBoldOnEmptyBlockDoesNothing() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.toggleBoldOnBlock(blockId)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText.isEmpty)
        #expect(content.textKind == TextItemKind.paragraph)
    }

    // MARK: - Cmd+I (Italic)

    @Test("Cmd+I wraps the focused item's whole text in '*…*'")
    func toggleItalicWrapsWholeText() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "Aside")

        viewModel.toggleItalicOnBlock(blockId)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText == "*Aside*")
    }

    @Test("Cmd+I a second time unwraps '*…*' back to plain text")
    func toggleItalicTwiceUnwraps() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "Aside")

        viewModel.toggleItalicOnBlock(blockId)
        viewModel.toggleItalicOnBlock(blockId)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText == "Aside")
    }

    @Test("Cmd+B then Cmd+I wraps '**bold**' text in '*…*' rather than misreading it as already-italic")
    func toggleItalicAfterBoldWrapsAgain() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "Strong")

        viewModel.toggleBoldOnBlock(blockId)
        viewModel.toggleItalicOnBlock(blockId)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText == "***Strong***")
    }

    // MARK: - Cmd+K (Link)

    @Test("Cmd+K wraps the focused item's whole text as a Markdown link with an empty URL placeholder")
    func toggleLinkWrapsWholeText() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "semi:bold")

        viewModel.toggleLinkOnBlock(blockId)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText == "[semi:bold]()")
    }

    @Test("Cmd+K on an already-linked whole item unwraps it back to plain text")
    func toggleLinkTwiceUnwraps() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "semi:bold")

        viewModel.toggleLinkOnBlock(blockId)
        viewModel.toggleLinkOnBlock(blockId)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText == "semi:bold")
    }

    @Test("Cmd+K on an empty item does nothing")
    func toggleLinkOnEmptyBlockDoesNothing() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.toggleLinkOnBlock(blockId)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText.isEmpty)
    }
}
