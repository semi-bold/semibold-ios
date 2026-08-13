import Testing

@testable import semibold

/// Tests for the iOS Slash Command bottom sheet's view-model side
/// (`quality-phase5` AC2, `tasks/NO-001.md` §12.2/§13.1):
///
/// - Typing a lone `/` into an empty paragraph item opens the sheet
///   (`slashCommandBlockId`) and clears the `/` back to an empty item.
/// - `convertBlock(_:toSlashCommandOption:)` converts that item to the
///   chosen `TextItemKind` and persists immediately, dismissing the sheet.
///
/// **NO-005 model note**: rewritten against the `DocumentItem`/
/// `TextContent` model (`tasks/NO-005.md` §3) — same triggers/assertions
/// as before, translated to `TextContent.textKind`/`plainText`/`isChecked`.
///
/// Split out from `DetailViewModelTests` following the
/// `HeadingConversionTests`/`KeyboardShortcutConversionTests` precedent —
/// keeps each suite's body within SwiftLint's `type_body_length`.
@MainActor
struct SlashCommandConversionTests {
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

    @Test("Typing '/' into an empty paragraph item opens the Slash Command sheet and clears the '/'")
    func typingSlashOpensSheetAndClearsText() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "/")

        #expect(viewModel.slashCommandBlockId == blockId)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "")

        // The cleared item is persisted immediately, not debounced.
        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.plainText == "")
    }

    @Test("'/' typed mid-sentence in a non-empty item doesn't open the sheet")
    func slashMidSentenceDoesNotOpenSheet() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "1/2")

        #expect(viewModel.slashCommandBlockId == nil)
        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "1/2")
    }

    @Test("'/' typed in a non-paragraph item doesn't open the sheet")
    func slashInNonParagraphBlockDoesNotOpenSheet() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        // First convert to a heading, then try '/' — shouldn't open the sheet.
        viewModel.updateBlockText(blockId, text: "# Title")
        viewModel.updateBlockText(blockId, text: "/")

        #expect(viewModel.slashCommandBlockId == nil)
        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.heading)
        #expect(content.plainText == "/")
    }

    @Test(
        "Picking a heading option converts the item to that heading level, empty, and dismisses the sheet",
        arguments: [
            (option: SlashCommandOption.heading1, level: 1),
            (option: SlashCommandOption.heading2, level: 2),
            (option: SlashCommandOption.heading3, level: 3)
        ]
    )
    func pickingHeadingOptionConvertsBlock(_ testCase: (option: SlashCommandOption, level: Int)) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "/")

        viewModel.convertBlock(blockId, toSlashCommandOption: testCase.option)

        #expect(viewModel.slashCommandBlockId == nil)
        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.heading)
        #expect(content.headingLevel == testCase.level)
        #expect(content.plainText == "")

        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.heading)
        #expect(stored.headingLevel == testCase.level)
    }

    @Test(
        "Picking a list/checklist/blockquote/code option converts the item to that type, empty",
        arguments: [
            SlashCommandOption.bulletedList,
            .numberedList,
            .checklist,
            .blockquote,
            .codeBlock
        ]
    )
    func pickingOtherOptionsConvertsBlock(_ option: SlashCommandOption) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "/")

        viewModel.convertBlock(blockId, toSlashCommandOption: option)

        #expect(viewModel.slashCommandBlockId == nil)
        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.plainText == "")

        switch option {
        case .bulletedList: #expect(content.textKind == TextItemKind.bulletedListItem)
        case .numberedList: #expect(content.textKind == TextItemKind.numberedListItem)
        case .checklist:
            #expect(content.textKind == TextItemKind.checklist)
            #expect(content.isChecked == false)
        case .blockquote: #expect(content.textKind == TextItemKind.quote)
        case .codeBlock: #expect(content.textKind == TextItemKind.codeBlock)
        default: Issue.record("Unexpected option \(option)")
        }

        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == content.textKind)
    }

    @Test("Picking Divider converts the item to a divider holding the literal '---' text")
    func pickingDividerConvertsBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "/")

        viewModel.convertBlock(blockId, toSlashCommandOption: .divider)

        #expect(viewModel.slashCommandBlockId == nil)
        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.divider)
        // Literal "---", not empty — tapping the rendered rule to edit it
        // needs real Markdown source text to show (`DividerBlockRow.body`'s
        // `ParagraphTextField`, `DetailScreen.swift`).
        #expect(content.plainText == "---")

        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.divider)
    }

    @Test("Dismissing the sheet without picking an option leaves the item an empty paragraph")
    func dismissingSheetLeavesEmptyParagraph() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "/")

        viewModel.dismissSlashCommand()

        #expect(viewModel.slashCommandBlockId == nil)
        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "")
    }
}
