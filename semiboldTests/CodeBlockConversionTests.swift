import Testing

@testable import semibold

/// Tests for `DetailViewModel.updateBlockText`'s code-block conversion
/// (`markdown-phase4` AC5): typing a ` ``` `/` ```<lang> ` fence converts a
/// paragraph block to `.codeBlock`, persisted immediately.
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

    @Test("Typing '```swift' converts the block to a code block with language 'swift', saved immediately")
    func typingFenceWithLanguageConvertsBlockToCodeBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            // A long debounce makes sure the code-block conversion below is
            // persisted immediately, not via the debounced path.
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "```swift")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .codeBlock)
        #expect(block.displayText == "")
        #expect(block.codeLanguage == "swift")
        #expect(block.contentJSON.contains("\"type\":\"code_block\""))
        #expect(block.contentJSON.contains("\"language\":\"swift\""))

        // markdownSource keeps the literal Markdown (with closing fence) for
        // round-tripping (§8.1).
        #expect(block.markdownSource == "```swift\n\n```")

        // Type conversion is a structural change — persisted immediately,
        // not waiting for the (long) debounce interval above.
        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.type == .codeBlock)
        #expect(stored.codeLanguage == "swift")
        #expect(stored.markdownSource == "```swift\n\n```")
    }

    @Test("Typing '```' alone converts the block to a code block with no language")
    func typingBareFenceConvertsBlockToCodeBlockWithNoLanguage() throws {
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

        viewModel.updateBlockText(blockId, text: "```")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .codeBlock)
        #expect(block.displayText == "")
        #expect(block.codeLanguage == nil)
        #expect(!block.contentJSON.contains("\"language\""))
        #expect(block.markdownSource == "```\n\n```")
    }

    @Test("Typing '```swift extra' keeps 'extra' as the code block's initial code")
    func typingFenceWithTrailingTextKeepsItAsInitialCode() throws {
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

        viewModel.updateBlockText(blockId, text: "```swift let x = 1")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .codeBlock)
        #expect(block.codeLanguage == "swift")
        #expect(block.displayText == "let x = 1")
        #expect(block.markdownSource == "```swift\nlet x = 1\n```")
    }

    @Test("Editing a code block keeps it a code block and rebuilds markdownSource with the fence")
    func editingCodeBlockRebuildsMarkdownSource() throws {
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

        viewModel.updateBlockText(blockId, text: "```swift")
        // Continue typing in the now-code-block — the displayed text (after
        // the fence) is what `ParagraphTextField` reports back.
        viewModel.updateBlockText(blockId, text: "let x = 1")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .codeBlock)
        #expect(block.codeLanguage == "swift")
        #expect(block.displayText == "let x = 1")
        #expect(block.markdownSource == "```swift\nlet x = 1\n```")
        #expect(block.contentJSON.contains("let x = 1"))
        #expect(block.contentJSON.contains("\"language\":\"swift\""))
    }

    @Test("'``' (two backticks) does NOT convert to a code block")
    func twoBackticksDoesNotConvert() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "``")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "``")
    }

    @Test("'`' (one backtick) does NOT convert to a code block")
    func oneBacktickDoesNotConvert() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "`")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "`")
    }

    @Test("'```' code-fence prefix doesn't conflict with heading/list/checklist/blockquote prefixes")
    func codeFencePrefixDoesNotConflictWithOtherPrefixes() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let blockRepository = DocumentBlockRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))

        for typedText in ["# Title", "- item", "1. item", "- [ ] task", "> quote"] {
            let block = try blockRepository.create(
                DocumentBlock(
                    documentId: document.id,
                    sortOrder: 0,
                    type: .paragraph,
                    contentJSON: BlockContent.paragraphJSON(text: "")
                )
            )
            let viewModel = DetailViewModel(
                document: document,
                documentBlockRepository: blockRepository,
                autosaveDebounceInterval: .seconds(10)
            )
            viewModel.load()

            viewModel.updateBlockText(block.id, text: typedText)

            let converted = try #require(viewModel.blocks.first(where: { $0.id == block.id }))
            #expect(converted.type != .codeBlock)
        }
    }
}
