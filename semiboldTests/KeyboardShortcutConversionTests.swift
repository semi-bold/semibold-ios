import Testing

@testable import semibold

/// Tests for `DetailViewModel+KeyboardShortcuts` — the view-model side of
/// macOS keyboard shortcuts (`tasks/NO-001.md` §13.2):
///
/// - Cmd+Option+1/2/3 → `convertBlockToHeading(_:level:)`
/// - Cmd+B / Cmd+I    → `toggleBoldOnBlock`/`toggleItalicOnBlock`
/// - Cmd+K            → `toggleLinkOnBlock`
///
/// Split out from `DetailViewModelTests` following the
/// `HeadingConversionTests`/`ChecklistConversionTests` precedent — keeps
/// each suite's body within SwiftLint's `type_body_length`.
@MainActor
struct KeyboardShortcutConversionTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    // MARK: - Cmd+Option+1/2/3 (Heading conversion)

    @Test(
        "Cmd+Option+1/2/3 converts the focused block to a heading at the matching level, saved immediately",
        arguments: [1, 2, 3]
    )
    func convertBlockToHeadingSetsLevelAndPersists(_ level: Int) throws {
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
        viewModel.updateBlockText(blockId, text: "Diary Entry")

        viewModel.convertBlockToHeading(blockId, level: level)

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .heading)
        #expect(block.displayText == "Diary Entry")
        #expect(block.headingLevel == level)
        #expect(block.markdownSource == String(repeating: "#", count: level) + " Diary Entry")

        // Structural change — persisted immediately.
        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.type == .heading)
        #expect(stored.headingLevel == level)
    }

    @Test("Cmd+Option+2 on an already-heading block re-levels it, keeping its text")
    func convertHeadingToDifferentLevelKeepsText() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "# Title")

        viewModel.convertBlockToHeading(blockId, level: 2)

        let block = try #require(viewModel.blocks.first)
        #expect(block.headingLevel == 2)
        #expect(block.displayText == "Title")
        #expect(block.markdownSource == "## Title")
    }

    // MARK: - Cmd+B (Bold)

    @Test("Cmd+B wraps the focused block's whole text in '**…**'")
    func toggleBoldWrapsWholeText() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "Important")

        viewModel.toggleBoldOnBlock(blockId)

        let block = try #require(viewModel.blocks.first)
        #expect(block.markdownSource == "**Important**")
        #expect(block.contentJSON.contains("\"marks\":[\"bold\"]"))
    }

    @Test("Cmd+B a second time unwraps '**…**' back to plain text")
    func toggleBoldTwiceUnwraps() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "Important")

        viewModel.toggleBoldOnBlock(blockId)
        viewModel.toggleBoldOnBlock(blockId)

        let block = try #require(viewModel.blocks.first)
        #expect(block.markdownSource == "Important")
        #expect(block.displayText == "Important")
    }

    @Test("Cmd+B on an empty block does nothing")
    func toggleBoldOnEmptyBlockDoesNothing() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.toggleBoldOnBlock(blockId)

        let block = try #require(viewModel.blocks.first)
        #expect(block.displayText.isEmpty)
        #expect(block.type == .paragraph)
    }

    // MARK: - Cmd+I (Italic)

    @Test("Cmd+I wraps the focused block's whole text in '*…*'")
    func toggleItalicWrapsWholeText() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "Aside")

        viewModel.toggleItalicOnBlock(blockId)

        let block = try #require(viewModel.blocks.first)
        #expect(block.markdownSource == "*Aside*")
        #expect(block.contentJSON.contains("\"marks\":[\"italic\"]"))
    }

    @Test("Cmd+I a second time unwraps '*…*' back to plain text")
    func toggleItalicTwiceUnwraps() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "Aside")

        viewModel.toggleItalicOnBlock(blockId)
        viewModel.toggleItalicOnBlock(blockId)

        let block = try #require(viewModel.blocks.first)
        #expect(block.markdownSource == "Aside")
    }

    @Test("Cmd+B then Cmd+I wraps '**bold**' text in '*…*' rather than misreading it as already-italic")
    func toggleItalicAfterBoldWrapsAgain() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "Strong")

        viewModel.toggleBoldOnBlock(blockId)
        viewModel.toggleItalicOnBlock(blockId)

        let block = try #require(viewModel.blocks.first)
        #expect(block.markdownSource == "***Strong***")
    }

    // MARK: - Cmd+K (Link)

    @Test("Cmd+K wraps the focused block's whole text as a Markdown link with an empty URL placeholder")
    func toggleLinkWrapsWholeText() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "semi:bold")

        viewModel.toggleLinkOnBlock(blockId)

        let block = try #require(viewModel.blocks.first)
        #expect(block.markdownSource == "[semi:bold]()")
        #expect(block.displayText == "[semi:bold]()")
    }

    @Test("Cmd+K on an already-linked whole block unwraps it back to plain text")
    func toggleLinkTwiceUnwraps() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "semi:bold")

        viewModel.toggleLinkOnBlock(blockId)
        viewModel.toggleLinkOnBlock(blockId)

        let block = try #require(viewModel.blocks.first)
        #expect(block.markdownSource == "semi:bold")
    }

    @Test("Cmd+K on an empty block does nothing")
    func toggleLinkOnEmptyBlockDoesNothing() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.toggleLinkOnBlock(blockId)

        let block = try #require(viewModel.blocks.first)
        #expect(block.displayText.isEmpty)
    }
}
