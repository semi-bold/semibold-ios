import GRDB
import Testing

@testable import semibold

/// Tests for `DetailViewModel.updateBlockText`'s checklist conversion
/// (`markdown-phase4` AC3): typing `- [ ] `/`- [x] ` converts a paragraph
/// block to `.checklistItem` (unchecked/checked) — taking precedence over
/// the `- ` bulleted-list conversion — plus `toggleChecklistItem`'s
/// checkbox toggle.
///
/// Split out from `DetailViewModelTests` (which covers the rest of
/// `DetailViewModel`'s editing/reorder behavior) to keep each suite's body
/// within SwiftLint's `type_body_length`.
@MainActor
struct ChecklistConversionTests {
    private func makeDatabaseManager() -> DatabaseManager {
        DatabaseManager(path: ":memory:")
    }

    @Test("Typing '- [ ] task' converts the block to an unchecked checklist item, saved immediately")
    func typingUncheckedChecklistPrefixConvertsBlockToChecklistItem() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            // A long debounce makes sure the checklist conversion below is
            // persisted immediately, not via the debounced path.
            autosaveDebounceInterval: .seconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "- [ ] task")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .checklistItem)
        #expect(block.displayText == "task")
        #expect(block.isChecked == false)
        #expect(block.contentJSON.contains("\"type\":\"checklist_item\""))
        #expect(block.contentJSON.contains("\"checked\":false"))
        #expect(block.contentJSON.contains("task"))

        // markdownSource keeps the literal Markdown the user typed, for
        // round-tripping (§8.1).
        #expect(block.markdownSource == "- [ ] task")

        // Type conversion is a structural change — persisted immediately,
        // not waiting for the (long) debounce interval above.
        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.type == .checklistItem)
        #expect(stored.displayText == "task")
        #expect(stored.isChecked == false)
        #expect(stored.markdownSource == "- [ ] task")
    }

    @Test("Typing '- [x] task' converts the block to a checked checklist item, saved immediately")
    func typingCheckedChecklistPrefixConvertsBlockToChecklistItem() throws {
        let database = makeDatabaseManager()
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

        viewModel.updateBlockText(blockId, text: "- [x] task")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .checklistItem)
        #expect(block.displayText == "task")
        #expect(block.isChecked == true)
        #expect(block.contentJSON.contains("\"checked\":true"))
        #expect(block.markdownSource == "- [x] task")

        let stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.type == .checklistItem)
        #expect(stored.displayText == "task")
        #expect(stored.isChecked == true)
        #expect(stored.markdownSource == "- [x] task")
    }

    @Test(
        "'- [ ] task'/'- [x] task' do NOT convert to a bulleted list item",
        arguments: [
            (prefix: "- [ ] ", checked: false),
            (prefix: "- [x] ", checked: true)
        ]
    )
    func checklistPrefixesDoNotConvertToBulletedList(_ testCase: (prefix: String, checked: Bool)) throws {
        let database = makeDatabaseManager()
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

        viewModel.updateBlockText(blockId, text: testCase.prefix + "task")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .checklistItem)
        #expect(block.type != .bulletedListItem)
        #expect(block.displayText == "task")
        #expect(block.isChecked == testCase.checked)
    }

    @Test("Editing a checklist item keeps its checked state and rebuilds markdownSource with the '- [ ]'/'- [x]' prefix")
    func editingChecklistItemKeepsCheckedStateAndPrefix() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(
            document: document,
            documentBlockRepository: blockRepository,
            autosaveDebounceInterval: .milliseconds(10)
        )
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: "- [x] task")
        // Continue typing in the now-checklist-item block — the displayed
        // text (no '- [x] ') is what `ParagraphTextField` reports back.
        viewModel.updateBlockText(blockId, text: "task, revised")

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .checklistItem)
        #expect(block.displayText == "task, revised")
        #expect(block.isChecked == true)
        #expect(block.markdownSource == "- [x] task, revised")
    }

    @Test("toggleChecklistItem flips the checked state, rebuilds markdownSource, and persists immediately")
    func toggleChecklistItemFlipsCheckedStateAndPersists() throws {
        let database = makeDatabaseManager()
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

        viewModel.updateBlockText(blockId, text: "- [ ] task")
        #expect(viewModel.blocks.first?.isChecked == false)

        viewModel.toggleChecklistItem(blockId: blockId)

        var block = try #require(viewModel.blocks.first)
        #expect(block.isChecked == true)
        #expect(block.displayText == "task")
        #expect(block.markdownSource == "- [x] task")

        var stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.isChecked == true)
        #expect(stored.markdownSource == "- [x] task")

        // Toggling again flips it back.
        viewModel.toggleChecklistItem(blockId: blockId)

        block = try #require(viewModel.blocks.first)
        #expect(block.isChecked == false)
        #expect(block.markdownSource == "- [ ] task")

        stored = try #require(try blockRepository.find(id: blockId))
        #expect(stored.isChecked == false)
        #expect(stored.markdownSource == "- [ ] task")
    }

    @Test("toggleChecklistItem does nothing for a non-checklist block")
    func toggleChecklistItemDoesNothingForNonChecklistBlock() throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)
        viewModel.updateBlockText(blockId, text: "Plain paragraph")

        viewModel.toggleChecklistItem(blockId: blockId)

        let block = try #require(viewModel.blocks.first)
        #expect(block.type == .paragraph)
        #expect(block.displayText == "Plain paragraph")
    }

    @Test(
        "'- [] task'/'- [X] task' don't trigger checklist conversion — fall through to bulleted-list '- '",
        arguments: ["- [] task", "- [X] task"]
    )
    func nonChecklistBracketSyntaxFallsThroughToBulletedList(_ typedText: String) throws {
        let database = makeDatabaseManager()
        let documentRepository = DocumentRepository(dbQueue: database.dbQueue)
        let blockRepository = DocumentBlockRepository(dbQueue: database.dbQueue)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = DetailViewModel(document: document, documentBlockRepository: blockRepository)
        viewModel.load()
        let blockId = try #require(viewModel.blocks.first?.id)

        viewModel.updateBlockText(blockId, text: typedText)

        let block = try #require(viewModel.blocks.first)
        #expect(block.type != .checklistItem)
        #expect(block.type == .bulletedListItem)
        // The "- " bulleted-list prefix is consumed, leaving the literal
        // "[ ]"/"[X]" text — these never become a checklist item.
        #expect(block.displayText == String(typedText.dropFirst(2)))
    }
}
