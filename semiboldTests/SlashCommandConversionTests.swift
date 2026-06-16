import GRDB
import Testing

@testable import semibold

/// Tests for the iOS Slash Command bottom sheet's view-model side
/// (`quality-phase5` AC2, `tasks/NO-001.md` §12.2/§13.1):
///
/// - Typing a lone `/` into an empty paragraph block opens the sheet
///   (`slashCommandBlockId`) and clears the `/` back to an empty block.
/// - `convertBlock(_:toSlashCommandOption:)` converts that block to the
///   chosen type and persists immediately, dismissing the sheet.
///
/// Split out from `DetailViewModelTests` following the
/// `HeadingConversionTests`/`KeyboardShortcutConversionTests` precedent —
/// keeps each suite's body within SwiftLint's `type_body_length`.
@MainActor
struct SlashCommandConversionTests {
    private func makeDatabaseManager() throws -> DatabaseManager {
        try DatabaseManager(path: ":memory:")
    }

    @Test("Typing '/' into an empty paragraph block opens the Slash Command sheet and clears the '/'")
    func typingSlashOpensSheetAndClearsText() throws {
        let database = try makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "/")

        #expect(viewModel.slashCommandBlockId == blockId)

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "")
        #expect(block.markdownSource == "")

        // The cleared block is persisted immediately, not debounced.
        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.displayText == "")
        #expect(stored.markdownSource == "")
    }

    @Test("'/' typed mid-sentence in a non-empty block doesn't open the sheet")
    func slashMidSentenceDoesNotOpenSheet() throws {
        let database = try makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "1/2")

        #expect(viewModel.slashCommandBlockId == nil)
        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "1/2")
    }

    @Test("'/' typed in a non-paragraph block doesn't open the sheet")
    func slashInNonParagraphBlockDoesNotOpenSheet() throws {
        let database = try makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        // First convert to a heading, then try '/' — shouldn't open the sheet.
        viewModel.updateBlockText(blockId, text: "# Title")
        viewModel.updateBlockText(blockId, text: "/")

        #expect(viewModel.slashCommandBlockId == nil)
        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .heading)
        #expect(block.displayText == "/")
    }

    @Test(
        "Picking a heading option converts the block to that heading level, empty, and dismisses the sheet",
        arguments: [
            (option: SlashCommandOption.heading1, level: 1),
            (option: SlashCommandOption.heading2, level: 2),
            (option: SlashCommandOption.heading3, level: 3)
        ]
    )
    func pickingHeadingOptionConvertsBlock(_ testCase: (option: SlashCommandOption, level: Int)) throws {
        let database = try makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "/")

        viewModel.convertBlock(blockId, toSlashCommandOption: testCase.option)

        #expect(viewModel.slashCommandBlockId == nil)
        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .heading)
        #expect(block.headingLevel == testCase.level)
        #expect(block.displayText == "")
        #expect(block.markdownSource == String(repeating: "#", count: testCase.level) + " ")

        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.type == .heading)
        #expect(stored.headingLevel == testCase.level)
    }

    @Test(
        "Picking a list/checklist/blockquote/code option converts the block to that type, empty",
        arguments: [
            SlashCommandOption.bulletedList,
            .numberedList,
            .checklist,
            .blockquote,
            .codeBlock
        ]
    )
    func pickingOtherOptionsConvertsBlock(_ option: SlashCommandOption) throws {
        let database = try makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "/")

        viewModel.convertBlock(blockId, toSlashCommandOption: option)

        #expect(viewModel.slashCommandBlockId == nil)
        let block = try #require(viewModel.blocks.first)
        #expect(block.displayText == "")

        switch option {
        case .bulletedList: #expect(block.type == .bulletedListItem)
        case .numberedList: #expect(block.type == .numberedListItem)
        case .checklist:
            #expect(block.type == .checklistItem)
            #expect(block.isChecked == false)
        case .blockquote: #expect(block.type == .blockquote)
        case .codeBlock: #expect(block.type == .codeBlock)
        default: Issue.record("Unexpected option \(option)")
        }

        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.type == block.type)
    }

    @Test("Picking Divider converts the block to a divider with no text content")
    func pickingDividerConvertsBlock() throws {
        let database = try makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "/")

        viewModel.convertBlock(blockId, toSlashCommandOption: .divider)

        #expect(viewModel.slashCommandBlockId == nil)
        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .divider)
        #expect(block.displayText == "")

        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.type == .divider)
    }

    @Test("Dismissing the sheet without picking an option leaves the block an empty paragraph")
    func dismissingSheetLeavesEmptyParagraph() throws {
        let database = try makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "/")

        viewModel.dismissSlashCommand()

        #expect(viewModel.slashCommandBlockId == nil)
        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "")
    }
}
