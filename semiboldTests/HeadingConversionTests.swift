import Testing

@testable import semibold

/// Tests for `DetailViewModel.updateBlockText`'s heading conversion
/// (`markdown-phase4` AC1): typing `# `/`## `/`### ` converts a paragraph
/// block to `.heading` at the matching level.
///
/// Split out from `DetailViewModelTests` (which covers the rest of
/// `DetailViewModel`'s editing/reorder behavior) to keep each suite's body
/// within SwiftLint's `type_body_length`.
@MainActor
struct HeadingConversionTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    @Test(
        "Typing '# ', '## ', '### ' converts the block to a heading of the matching level, saved immediately",
        arguments: [
            (prefix: "# ", level: 1),
            (prefix: "## ", level: 2),
            (prefix: "### ", level: 3)
        ]
    )
    func typingHeadingPrefixConvertsBlockToHeading(_ testCase: (prefix: String, level: Int)) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            // A long debounce makes sure the heading conversion below is
            // persisted immediately, not via the debounced path.
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: testCase.prefix + "Title")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .heading)
        #expect(block.displayText == "Title")
        #expect(block.headingLevel == testCase.level)
        #expect(block.contentJSON.contains("\"type\":\"heading\""))
        #expect(block.contentJSON.contains("\"level\":\(testCase.level)"))
        #expect(block.contentJSON.contains("Title"))

        // markdownSource keeps the literal Markdown the user typed, for
        // round-tripping (§8.1).
        #expect(block.markdownSource == testCase.prefix + "Title")

        // Type conversion is a structural change — persisted immediately,
        // not waiting for the (long) debounce interval above.
        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.type == .heading)
        #expect(stored.displayText == "Title")
        #expect(stored.headingLevel == testCase.level)
        #expect(stored.markdownSource == testCase.prefix + "Title")
    }

    @Test("Editing a heading block's text keeps its level and rebuilds markdownSource with the '#' prefix")
    func editingHeadingBlockKeepsLevelAndPrefix() throws {
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

        viewModel.updateBlockText(blockId, text: "## Heading")
        // Continue typing in the now-heading block — the displayed text
        // (no '#') is what `ParagraphTextField` reports back.
        viewModel.updateBlockText(blockId, text: "Heading 2")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .heading)
        #expect(block.displayText == "Heading 2")
        #expect(block.headingLevel == 2)
        #expect(block.markdownSource == "## Heading 2")
    }

    @Test("A 4th '#' doesn't trigger heading conversion")
    func fourHashesDoesNotConvert() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "#### Title")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "#### Title")
    }

    @Test("A '#' without a trailing space doesn't trigger heading conversion")
    func hashWithoutSpaceDoesNotConvert() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "#hashtag")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "#hashtag")
    }
}
