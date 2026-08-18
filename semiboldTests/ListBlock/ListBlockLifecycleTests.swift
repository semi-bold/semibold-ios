import Testing

@testable import semibold

/// One place to see every user action that can affect a list block's
/// nesting state (`depth`/`listGroupId`) — a catalog, not a replacement
/// for the existing focused test files (`DetailViewModelTests.swift`'s
/// indent/outdent section, `ListIndentOutdentWiringTests.swift`). Some
/// cases here duplicate coverage that already exists elsewhere
/// (deliberately — the point of this file is being able to read one
/// place and know whether list nesting holds together end to end,
/// without re-deriving it from `DetailViewModel`'s source).
///
/// Sections mirror this directory's `README.md` — **read that first**,
/// it's the plain-language policy this file's tests translate into code:
/// - A. 텍스트 타이핑으로 리스트 생성/전환 (`updateBlockText`)
/// - B. Enter 키 (`insertBlock`)
/// - C. Backspace 키 (`mergeOrDeleteBlock`)
/// - D. 슬래시 커맨드 (`convertBlock(_:toSlashCommandOption:)`)
/// - F. 리스트 전용 액션 (`indentBlock`/`outdentBlock`/`toggleChecklistItem`)
///
/// (No E section here — README's E1 (Cmd+B/I/K) has no list-state effect
/// and is already covered by `KeyboardShortcutConversionTests.swift`.)
///
/// Cases marked `.disabled(...)` document a known gap — the *expected*
/// behavior once fixed, not what happens today. Removing the `.disabled`
/// trait is the acceptance check for that fix.
@MainActor
struct ListBlockLifecycleTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    private func makeViewModel(document: Document, store: CoreDataTestStore) -> DetailViewModel {
        DetailViewModel(
            document: document,
            documentItemRepository: DocumentItemRepository(context: store.context),
            textItemRepository: TextItemRepository(context: store.context),
            textMarkRepository: TextMarkRepository(context: store.context),
            mediaItemRepository: MediaItemRepository(context: store.context),
            listGroupRepository: ListGroupRepository(context: store.context),
            folderRepository: FolderRepository(context: store.context)
        )
    }

    /// Builds a `DocumentItem` + `TextContent` directly through the
    /// repositories, bypassing `DetailViewModel`'s own conversion paths,
    /// so a test can set up an already-nested outline before exercising
    /// the action under test.
    @discardableResult
    private func createItem(
        documentId: String,
        depth: Int = 0,
        listGroupId: String? = nil,
        orderKey: String,
        textKind: String,
        text: String,
        documentItemRepository: DocumentItemRepository,
        textItemRepository: TextItemRepository
    ) throws -> DocumentItem {
        let item = try documentItemRepository.create(
            DocumentItem(
                documentId: documentId, depth: depth, listGroupId: listGroupId, contentType: "text", orderKey: orderKey
            )
        )
        _ = try textItemRepository.create(TextContent(itemId: item.id, textKind: textKind, plainText: text))
        return item
    }

    // MARK: - A. 텍스트 타이핑으로 리스트 생성/전환 (`updateBlockText`)

    @Test("A2: Typing '- ' into an empty document's first block creates a fresh list group")
    func a2_typingListPrefixIntoFirstBlockCreatesFreshGroup() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)

        viewModel.updateBlockText(blockId, text: "- item")

        let stored = try #require(try documentItemRepository.find(id: blockId))
        #expect(stored.depth == 0)
        #expect(stored.listGroupId != nil)
    }

    @Test("A2: Typing '- ' right after an existing bulleted item joins that item's group, not a new one")
    func a2_typingListPrefixAfterExistingListJoinsItsGroup() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let listGroup = try ListGroupRepository(context: store.context).create(
            ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem)
        )
        let firstItem = try createItem(
            documentId: document.id, listGroupId: listGroup.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem, text: "First",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let secondBlock = try documentItemRepository.create(
            DocumentItem(documentId: document.id, orderKey: OrderKey.between(firstItem.orderKey, nil))
        )
        _ = try textItemRepository.create(TextContent(itemId: secondBlock.id, textKind: TextItemKind.paragraph, plainText: ""))

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.updateBlockText(secondBlock.id, text: "- second")

        let stored = try #require(try documentItemRepository.find(id: secondBlock.id))
        #expect(stored.listGroupId == listGroup.id)
    }

    @Test(
        "A2 GAP: converting a block sandwiched between two same-kind list groups should merge all three into one",
        .disabled("group merge on structural adjacency isn't implemented yet — see ListBlock/README.md")
    )
    func a2_convertingBlockBetweenTwoGroupsMergesThem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let groupA = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let groupB = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let itemA = try createItem(
            documentId: document.id, listGroupId: groupA.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem, text: "A",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let middleBlock = try documentItemRepository.create(
            DocumentItem(documentId: document.id, orderKey: OrderKey.between(itemA.orderKey, nil))
        )
        _ = try textItemRepository.create(TextContent(itemId: middleBlock.id, textKind: TextItemKind.paragraph, plainText: ""))
        let itemB = try createItem(
            documentId: document.id, listGroupId: groupB.id, orderKey: OrderKey.between(middleBlock.orderKey, nil),
            textKind: TextItemKind.bulletedListItem, text: "B",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.updateBlockText(middleBlock.id, text: "- middle")

        let storedA = try #require(try documentItemRepository.find(id: itemA.id))
        let storedMiddle = try #require(try documentItemRepository.find(id: middleBlock.id))
        let storedB = try #require(try documentItemRepository.find(id: itemB.id))
        // 첫 번째(가장 먼저 나온) 그룹으로 전부 합쳐진다.
        #expect(storedMiddle.listGroupId == storedA.listGroupId)
        #expect(storedB.listGroupId == storedA.listGroupId)
    }

    @Test("A3: Upgrading a bulleted item to a checklist (typing '[ ] ' after '- ') keeps its depth and group")
    func a3_bulletedToChecklistUpgradeKeepsDepthAndGroup() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let blockId = try #require(viewModel.items.first?.id)
        viewModel.updateBlockText(blockId, text: "- ")
        let depthBefore = try #require(try documentItemRepository.find(id: blockId)).depth
        let groupBefore = try #require(try documentItemRepository.find(id: blockId)).listGroupId

        // "- " already converted this block, so continuing to type only
        // appends to its now-empty remainder — not re-typing "- ".
        viewModel.updateBlockText(blockId, text: "[ ] task")

        #expect(viewModel.textContent(forItemId: blockId).textKind == TextItemKind.checklist)
        let stored = try #require(try documentItemRepository.find(id: blockId))
        #expect(stored.depth == depthBefore)
        #expect(stored.listGroupId == groupBefore)
    }

    // MARK: - B. Enter 키 (`insertBlock`)

    @Test("B1: Enter on a non-empty nested list item continues with the same depth and group")
    func b1_enterOnNestedListItemContinuesSameDepthAndGroup() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let group = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let nestedItem = try createItem(
            documentId: document.id, depth: 1, listGroupId: group.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem, text: "Nested",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.insertBlock(after: nestedItem.id, currentText: "Nested", cursorOffset: "Nested".count)

        let newBlockId = try #require(viewModel.items.last?.id)
        #expect(viewModel.textContent(forItemId: newBlockId).textKind == TextItemKind.bulletedListItem)
        let stored = try #require(try documentItemRepository.find(id: newBlockId))
        #expect(stored.depth == 1)
        #expect(stored.listGroupId == group.id)
    }

    @Test(
        "B2 GAP: Enter on an empty nested list item (exit to paragraph) shifts its own descendants up one depth",
        .disabled("exitEmptyListItem doesn't cascade depth to descendants yet — see ListBlock/README.md")
    )
    func b2_enterOnEmptyNestedListItemCascadesDescendantDepth() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let group = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let parent = try createItem(
            documentId: document.id, listGroupId: group.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem, text: "Parent",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let empty = try createItem(
            documentId: document.id, depth: 1, listGroupId: group.id, orderKey: OrderKey.between(parent.orderKey, nil),
            textKind: TextItemKind.bulletedListItem, text: "",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let child = try createItem(
            documentId: document.id, depth: 2, listGroupId: group.id, orderKey: OrderKey.between(empty.orderKey, nil),
            textKind: TextItemKind.bulletedListItem, text: "Child",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.insertBlock(after: empty.id, currentText: "", cursorOffset: 0)

        #expect(viewModel.textContent(forItemId: empty.id).textKind == TextItemKind.paragraph)
        #expect(viewModel.depth(forItemId: child.id) == 1)
    }

    // MARK: - C. Backspace 키 (`mergeOrDeleteBlock`)

    @Test("C1: Backspace on an empty nested list item exits it to a plain paragraph in place")
    func c1_backspaceOnEmptyListItemExitsInPlace() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let group = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let parent = try createItem(
            documentId: document.id, listGroupId: group.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem, text: "Parent",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let empty = try createItem(
            documentId: document.id, depth: 1, listGroupId: group.id, orderKey: OrderKey.between(parent.orderKey, nil),
            textKind: TextItemKind.bulletedListItem, text: "",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.mergeOrDeleteBlock(empty.id, currentText: "")

        #expect(viewModel.items.map(\.id) == [parent.id, empty.id])
        #expect(viewModel.textContent(forItemId: empty.id).textKind == TextItemKind.paragraph)
        let stored = try #require(try documentItemRepository.find(id: empty.id))
        #expect(stored.depth == 0)
        #expect(stored.listGroupId == nil)
    }

    @Test("C2: Backspace at the start of a non-empty heading reverts it to a paragraph, keeping its text")
    func c2_backspaceOnNonEmptyHeadingRevertsToParagraphKeepingText() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let heading = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.heading, text: "Title",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.mergeOrDeleteBlock(heading.id, currentText: "Title")

        // Block stays put — it's converted in place, not merged/removed.
        #expect(viewModel.items.map(\.id) == [heading.id])
        let content = viewModel.textContent(forItemId: heading.id)
        #expect(content.textKind == TextItemKind.paragraph)
        #expect(content.plainText == "Title")
    }

    @Test("C2: Backspace at the start of an empty heading also reverts it to a paragraph (no emptiness gate, unlike C1)")
    func c2_backspaceOnEmptyHeadingRevertsToParagraph() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let heading = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.heading, text: "",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.mergeOrDeleteBlock(heading.id, currentText: "")

        #expect(viewModel.items.map(\.id) == [heading.id])
        #expect(viewModel.textContent(forItemId: heading.id).textKind == TextItemKind.paragraph)
    }

    @Test("C2: Backspace on a heading sitting between two same-kind list groups does not merge them (the heading never leaves the array)")
    func c2_backspaceOnHeadingBetweenListGroupsDoesNotMergeThem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let groupA = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let groupB = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let itemA = try createItem(
            documentId: document.id, listGroupId: groupA.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem, text: "A",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let heading = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemA.orderKey, nil),
            textKind: TextItemKind.heading, text: "Section",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemB = try createItem(
            documentId: document.id, listGroupId: groupB.id, orderKey: OrderKey.between(heading.orderKey, nil),
            textKind: TextItemKind.bulletedListItem, text: "B",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.mergeOrDeleteBlock(heading.id, currentText: "Section")

        #expect(viewModel.items.map(\.id) == [itemA.id, heading.id, itemB.id])
        let storedA = try #require(try documentItemRepository.find(id: itemA.id))
        let storedB = try #require(try documentItemRepository.find(id: itemB.id))
        #expect(storedA.listGroupId == groupA.id)
        #expect(storedB.listGroupId == groupB.id)
    }

    @Test(
        "C3 GAP: Backspace-removing a list item shifts its own descendants up one depth",
        .disabled("mergeOrDeleteBlock doesn't cascade depth to the removed item's descendants yet — see ListBlock/README.md")
    )
    func c3_backspaceRemovingListItemCascadesDescendantDepth() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let group = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let line1 = try createItem(
            documentId: document.id, listGroupId: group.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem, text: "line1",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let line2 = try createItem(
            documentId: document.id, depth: 1, listGroupId: group.id, orderKey: OrderKey.between(line1.orderKey, nil),
            textKind: TextItemKind.bulletedListItem, text: "line2",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let line3 = try createItem(
            documentId: document.id, depth: 2, listGroupId: group.id, orderKey: OrderKey.between(line2.orderKey, nil),
            textKind: TextItemKind.bulletedListItem, text: "line3",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // Backspace at the very start of line2, with its text non-empty —
        // merges into line1 and removes line2 outright (not the
        // exit-empty-list-item path).
        viewModel.mergeOrDeleteBlock(line2.id, currentText: "line2")

        #expect(viewModel.items.map(\.id) == [line1.id, line3.id])
        #expect(viewModel.depth(forItemId: line3.id) == 1)
    }

    @Test(
        "C3 GAP: Backspace-removing a block between two same-kind list groups merges them",
        .disabled("group merge on structural adjacency isn't implemented yet — see ListBlock/README.md")
    )
    func c3_backspaceRemovingSeparatorMergesAdjacentGroups() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let groupA = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let groupB = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let line3 = try createItem(
            documentId: document.id, listGroupId: groupA.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem, text: "line3",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let line4 = try documentItemRepository.create(
            DocumentItem(documentId: document.id, orderKey: OrderKey.between(line3.orderKey, nil))
        )
        _ = try textItemRepository.create(TextContent(itemId: line4.id, textKind: TextItemKind.paragraph, plainText: ""))
        let line5 = try createItem(
            documentId: document.id, listGroupId: groupB.id, orderKey: OrderKey.between(line4.orderKey, nil),
            textKind: TextItemKind.bulletedListItem, text: "line5",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.mergeOrDeleteBlock(line4.id, currentText: "")

        let storedLine3 = try #require(try documentItemRepository.find(id: line3.id))
        let storedLine5 = try #require(try documentItemRepository.find(id: line5.id))
        #expect(storedLine5.listGroupId == storedLine3.listGroupId)
    }

    // MARK: - D. 슬래시 커맨드 (`convertBlock(_:toSlashCommandOption:)`)

    @Test("D1: Picking Bulleted List from the slash command menu right after an existing bulleted item joins its group")
    func d1_slashCommandBulletedListAfterExistingListJoinsGroup() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let listGroup = try ListGroupRepository(context: store.context).create(
            ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem)
        )
        let firstItem = try createItem(
            documentId: document.id, listGroupId: listGroup.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem, text: "First",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let secondBlock = try documentItemRepository.create(
            DocumentItem(documentId: document.id, orderKey: OrderKey.between(firstItem.orderKey, nil))
        )
        _ = try textItemRepository.create(TextContent(itemId: secondBlock.id, textKind: TextItemKind.paragraph, plainText: ""))

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.convertBlock(secondBlock.id, toSlashCommandOption: .bulletedList)

        let stored = try #require(try documentItemRepository.find(id: secondBlock.id))
        #expect(stored.listGroupId == listGroup.id)
    }

    // MARK: - F. 리스트 전용 액션 (`indentBlock`/`outdentBlock`)

    @Test("F1: Indenting a list item with an eligible previous sibling nests it, keeping the same group")
    func f1_indentEligibleSiblingKeepsGroup() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let group = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let firstItem = try createItem(
            documentId: document.id, listGroupId: group.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem, text: "First",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let secondItem = try createItem(
            documentId: document.id, listGroupId: group.id, orderKey: OrderKey.between(firstItem.orderKey, nil),
            textKind: TextItemKind.bulletedListItem, text: "Second",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.indentBlock(secondItem.id)

        #expect(viewModel.depth(forItemId: secondItem.id) == 1)
        let stored = try #require(try documentItemRepository.find(id: secondItem.id))
        #expect(stored.listGroupId == group.id)
    }

    @Test(
        "F2 GAP: Outdenting an item into a position adjacent to a different same-kind group merges them",
        .disabled("group merge on structural adjacency isn't implemented yet — see ListBlock/README.md")
    )
    func f2_outdentIntoAdjacentGroupMergesThem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let groupA = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let groupB = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))
        let a1 = try createItem(
            documentId: document.id, listGroupId: groupA.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem, text: "a1",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let a2 = try createItem(
            documentId: document.id, depth: 1, listGroupId: groupA.id, orderKey: OrderKey.between(a1.orderKey, nil),
            textKind: TextItemKind.bulletedListItem, text: "a2",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let b1 = try createItem(
            documentId: document.id, listGroupId: groupB.id, orderKey: OrderKey.between(a2.orderKey, nil),
            textKind: TextItemKind.bulletedListItem, text: "b1",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        #expect(viewModel.items.map(\.id) == [a1.id, a2.id, b1.id])

        viewModel.outdentBlock(a2.id) // a2 promotes to top-level, landing right before b1.

        #expect(viewModel.items.map(\.id) == [a1.id, a2.id, b1.id])
        let storedA2 = try #require(try documentItemRepository.find(id: a2.id))
        let storedB1 = try #require(try documentItemRepository.find(id: b1.id))
        #expect(storedB1.listGroupId == storedA2.listGroupId)
    }

    @Test("F3: Toggling a checklist item's checked state doesn't touch its depth or group")
    func f3_toggleChecklistItemLeavesDepthAndGroupUntouched() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let group = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.checklist))
        let item = try createItem(
            documentId: document.id, depth: 1, listGroupId: group.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.checklist, text: "task",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        viewModel.toggleChecklistItem(blockId: item.id)

        #expect(viewModel.textContent(forItemId: item.id).isChecked == true)
        let stored = try #require(try documentItemRepository.find(id: item.id))
        #expect(stored.depth == 1)
        #expect(stored.listGroupId == group.id)
    }
}
