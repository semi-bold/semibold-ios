import Testing

@testable import semibold

/// Tests for `DetailViewModel.updateBlockText`'s checklist conversion
/// (`markdown-phase4` AC3): typing `- [ ] `/`- [x] ` converts a paragraph
/// item to `TextItemKind.checklist` (unchecked/checked) — taking
/// precedence over the `- ` bulleted-list conversion — plus
/// `toggleChecklistItem`'s checkbox toggle.
///
/// **NO-005 model note**: rewritten against the `DocumentItem`/
/// `TextContent` model (`tasks/NO-005.md` §3) — same typed-input/
/// assertions as before, translated to `TextContent.textKind`/`isChecked`.
///
/// Split out from `DetailViewModelTests` (which covers the rest of
/// `DetailViewModel`'s editing/reorder behavior) to keep each suite's body
/// within SwiftLint's `type_body_length`.
@MainActor
struct ChecklistConversionTests {
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

    @Test("Typing '- [ ] task' converts the item to an unchecked checklist item, saved immediately")
    func typingUncheckedChecklistPrefixConvertsBlockToChecklistItem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        // A long debounce makes sure the checklist conversion below is
        // persisted immediately, not via the debounced path.
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "- [ ] task")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.checklist)
        #expect(content.plainText == "task")
        #expect(content.isChecked == false)

        // Type conversion is a structural change — persisted immediately,
        // not waiting for the (long) debounce interval above.
        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.checklist)
        #expect(stored.plainText == "task")
        #expect(stored.isChecked == false)
    }

    @Test("Typing '- [x] task' converts the item to a checked checklist item, saved immediately")
    func typingCheckedChecklistPrefixConvertsBlockToChecklistItem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "- [x] task")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.checklist)
        #expect(content.plainText == "task")
        #expect(content.isChecked == true)

        let stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.textKind == TextItemKind.checklist)
        #expect(stored.plainText == "task")
        #expect(stored.isChecked == true)
    }

    @Test(
        "'- [ ] task'/'- [x] task' do NOT convert to a bulleted list item",
        arguments: [
            (prefix: "- [ ] ", checked: false),
            (prefix: "- [x] ", checked: true)
        ]
    )
    func checklistPrefixesDoNotConvertToBulletedList(_ testCase: (prefix: String, checked: Bool)) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: testCase.prefix + "task")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.checklist)
        #expect(content.textKind != TextItemKind.bulletedListItem)
        #expect(content.plainText == "task")
        #expect(content.isChecked == testCase.checked)
    }

    @Test("Editing a checklist item keeps its checked state and updates plainText")
    func editingChecklistItemKeepsCheckedStateAndPrefix() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .milliseconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "- [x] task")
        // Continue typing in the now-checklist-item block — the displayed
        // text (no '- [x] ') is what `ParagraphTextField` reports back.
        viewModel.updateBlockText(blockId, text: "task, revised")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.checklist)
        #expect(content.plainText == "task, revised")
        #expect(content.isChecked == true)
    }

    @Test("toggleChecklistItem flips the checked state and persists immediately")
    func toggleChecklistItemFlipsCheckedStateAndPersists() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "- [ ] task")
        #expect(viewModel.textContent(forItemId: blockId).isChecked == false)

        viewModel.toggleChecklistItem(blockId: blockId)

        var content = viewModel.textContent(forItemId: blockId)
        #expect(content.isChecked == true)
        #expect(content.plainText == "task")

        var stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.isChecked == true)

        // Toggling again flips it back.
        viewModel.toggleChecklistItem(blockId: blockId)

        content = viewModel.textContent(forItemId: blockId)
        #expect(content.isChecked == false)

        stored = try #require(try textItemRepository.find(itemId: blockId))
        #expect(stored.isChecked == false)
    }

    @Test("toggleChecklistItem does nothing for a non-checklist block")
    func toggleChecklistItemDoesNothingForNonChecklistBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "Plain paragraph")

        viewModel.toggleChecklistItem(blockId: blockId)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "Plain paragraph")
    }

    @Test(
        """
        Typing '- ' then '[ ] '/'[x] ' one keystroke at a time (as `ParagraphTextField` really delivers it, via \
        `updateBlockText` on every change — not as one final string) still ends up a checklist item, not stuck \
        as a bulleted list. Regression test: `"- "` alone converts the block to `.bulletedListItem` immediately \
        (unchanged, existing behavior) — `checklistUpgradeFromBulletedListItem` is what then catches `"[ ] "`/ \
        `"[x] "` typed right after and upgrades that bulleted item to a checklist item, since without it the \
        brackets would just become literal bullet text and `"- [ ] task"` typed naturally could never become a \
        checklist
        """,
        arguments: [
            (afterBulletKeystrokes: ["[", "[ ", "[ ]", "[ ] "], checked: false),
            (afterBulletKeystrokes: ["[", "[x", "[x]", "[x] "], checked: true)
        ]
    )
    func typingChecklistBracketsAfterBulletOneKeystrokeAtATimeUpgradesToChecklist(
        _ testCase: (afterBulletKeystrokes: [String], checked: Bool)
    ) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        // "- " converts to a bulleted list item immediately, same as
        // always — the bullet's own prefix is already stripped, so what
        // `ParagraphTextField` reports from here on is just the brackets
        // themselves, not re-prefixed with "- ".
        viewModel.updateBlockText(blockId, text: "- ")
        #expect(viewModel.textContent(forItemId: blockId).textKind == TextItemKind.bulletedListItem)

        for keystroke in testCase.afterBulletKeystrokes {
            viewModel.updateBlockText(blockId, text: keystroke)
        }

        // The bracket prefix alone should have already upgraded the block
        // to a checklist — every intermediate keystroke above ("[", "[ ",
        // "[ ]") must have stayed a bulleted list item with that literal
        // text, or this would have upgraded too early.
        #expect(viewModel.textContent(forItemId: blockId).textKind == TextItemKind.checklist)
        #expect(viewModel.textContent(forItemId: blockId).plainText == "")

        // The rest of "task" is typed only after the bracket prefix has
        // already converted the block, exactly like `ParagraphTextField`
        // reporting its now-cleared text plus each subsequent character.
        viewModel.updateBlockText(blockId, text: "task")

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.checklist)
        #expect(content.textKind != TextItemKind.bulletedListItem)
        #expect(content.plainText == "task")
        #expect(content.isChecked == testCase.checked)
    }

    @Test("Typing '- item' (no brackets) one keystroke at a time stays a bulleted list, never upgrading")
    func typingPlainBulletedListItemOneKeystrokeAtATimeStaysBulletedList() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store, autosaveDebounceInterval: .seconds(10))
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "- ")
        #expect(viewModel.textContent(forItemId: blockId).textKind == TextItemKind.bulletedListItem)

        // The "- " prefix is already stripped at this point, so the rest
        // of "item" is typed onto the (empty) remaining text, not
        // re-prefixed with "- " — matching what `ParagraphTextField`
        // actually reports once the block has converted.
        for keystroke in ["i", "it", "item"] {
            viewModel.updateBlockText(blockId, text: keystroke)
        }

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind == TextItemKind.bulletedListItem)
        #expect(content.plainText == "item")
    }

    @Test(
        "'- [] task'/'- [X] task' don't trigger checklist conversion — fall through to bulleted-list '- '",
        arguments: ["- [] task", "- [X] task"]
    )
    func nonChecklistBracketSyntaxFallsThroughToBulletedList(_ typedText: String) throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: typedText)

        let content = viewModel.textContent(forItemId: blockId)
        #expect(content.textKind != TextItemKind.checklist)
        #expect(content.textKind == TextItemKind.bulletedListItem)
        // The "- " bulleted-list prefix is consumed, leaving the literal
        // "[ ]"/"[X]" text — these never become a checklist item.
        #expect(content.plainText == String(typedText.dropFirst(2)))
    }
}
