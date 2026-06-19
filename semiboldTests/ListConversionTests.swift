import Testing

@testable import semibold

/// Tests for `DetailViewModel.updateBlockText`'s list conversion
/// (`markdown-phase4` AC2): typing `- ` converts a paragraph block to
/// `.bulletedListItem`, and `<n>. ` converts it to `.numberedListItem`.
///
/// Split out from `DetailViewModelTests` (which covers the rest of
/// `DetailViewModel`'s editing/reorder behavior) to keep each suite's body
/// within SwiftLint's `type_body_length`.
@MainActor
struct ListConversionTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    @Test("Typing '- item' converts the block to a bulleted list item, saved immediately")
    func typingHyphenSpacePrefixConvertsBlockToBulletedListItem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            // A long debounce makes sure the list conversion below is
            // persisted immediately, not via the debounced path.
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "- Milk")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .bulletedListItem)
        #expect(block.displayText == "Milk")
        #expect(block.contentJSON.contains("\"type\":\"bulleted_list_item\""))
        #expect(block.contentJSON.contains("Milk"))

        // markdownSource keeps the literal Markdown the user typed, for
        // round-tripping (§8.1).
        #expect(block.markdownSource == "- Milk")

        // Type conversion is a structural change — persisted immediately,
        // not waiting for the (long) debounce interval above.
        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.type == .bulletedListItem)
        #expect(stored.displayText == "Milk")
        #expect(stored.markdownSource == "- Milk")
    }

    @Test("Typing '1. item' converts the block to a numbered list item, saved immediately")
    func typingNumberDotSpacePrefixConvertsBlockToNumberedListItem() throws {
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

        viewModel.updateBlockText(blockId, text: "1. First step")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .numberedListItem)
        #expect(block.displayText == "First step")
        #expect(block.numberedListNumber == 1)
        #expect(block.contentJSON.contains("\"type\":\"numbered_list_item\""))
        #expect(block.contentJSON.contains("First step"))
        #expect(block.markdownSource == "1. First step")

        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.type == .numberedListItem)
        #expect(stored.displayText == "First step")
        #expect(stored.markdownSource == "1. First step")
    }

    @Test("A multi-digit numbered list prefix keeps its literal number")
    func multiDigitNumberedListPrefixKeepsLiteralNumber() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "42. Answer")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .numberedListItem)
        #expect(block.displayText == "Answer")
        #expect(block.numberedListNumber == 42)
        #expect(block.markdownSource == "42. Answer")
    }

    @Test("Editing a bulleted list item keeps its type and rebuilds markdownSource with the '- ' prefix")
    func editingBulletedListItemKeepsTypeAndPrefix() throws {
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

        viewModel.updateBlockText(blockId, text: "- Milk")
        // Continue typing in the now-list-item block — the displayed text
        // (no '- ') is what `ParagraphTextField` reports back.
        viewModel.updateBlockText(blockId, text: "Milk and eggs")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .bulletedListItem)
        #expect(block.displayText == "Milk and eggs")
        #expect(block.markdownSource == "- Milk and eggs")
    }

    @Test("Editing a numbered list item keeps its number and rebuilds markdownSource with the '<n>. ' prefix")
    func editingNumberedListItemKeepsNumberAndPrefix() throws {
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

        viewModel.updateBlockText(blockId, text: "2. Step two")
        viewModel.updateBlockText(blockId, text: "Step two, revised")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .numberedListItem)
        #expect(block.displayText == "Step two, revised")
        #expect(block.numberedListNumber == 2)
        #expect(block.markdownSource == "2. Step two, revised")
    }

    @Test("'-item' without a space doesn't trigger bulleted list conversion")
    func hyphenWithoutSpaceDoesNotConvertToBulletedList() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "-item")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "-item")
    }

    @Test("'-- item' doesn't trigger bulleted list conversion")
    func doubleHyphenDoesNotConvertToBulletedList() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "-- item")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "-- item")
    }

    @Test("A digit without '. ' doesn't trigger numbered list conversion")
    func digitWithoutDotSpaceDoesNotConvertToNumberedList() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "1 item")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "1 item")
    }

    @Test("'1.item' without a space after the period doesn't trigger numbered list conversion")
    func digitDotWithoutSpaceDoesNotConvertToNumberedList() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "1.item")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "1.item")
    }
}
