import SwiftUI
import Testing

@testable import semibold

/// Tests confirming the `onIndent`/`onOutdent` wiring the
/// `04-tab-key-hardware-interception` brief adds actually reaches
/// `DetailViewModel.indentBlock`/`.outdentBlock` with the right block id —
/// at the closure level, per that brief's Decisions (simulating a real
/// hardware Tab/Shift+Tab press isn't practical in `XCTest`/Swift Testing,
/// so these call the closures directly instead, the same way UIKit itself
/// would once `IndentableTextViewTests` confirms it resolves a real key
/// press to the right target-action).
///
/// Two things are checked:
/// - The three list-kind `*BlockView.chrome(...)` factories
///   (`BulletedListBlockView`/`NumberedListBlockView`/`ChecklistBlockView`)
///   forward whatever `onIndent`/`onOutdent` closures they're given
///   straight through to the `BlockRowChrome` they return, unchanged.
/// - `DetailScreen.blockRow(for:content:)`'s own closures — `{ viewModel
///   .indentBlock(item.id) }` / `{ viewModel.outdentBlock(item.id) }` —
///   drive the right item when called. `blockRow` itself is a private
///   method on a `View` struct with a live `@FocusState`, so it isn't
///   directly reachable from a test; these reproduce its exact closure
///   literals (readable side by side with `DetailScreen.swift`) against a
///   real `DetailViewModel`/Core Data test store instead, which is the
///   part that can go wrong (a stale-captured id, a mixed-up indent/outdent
///   call) even though the closures superficially look right.
@MainActor
struct ListIndentOutdentWiringTests {
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
            folderRepository: FolderRepository(context: store.context)
        )
    }

    /// Same helper as `DetailViewModelTests.createItem` — builds a
    /// `DocumentItem` + `TextContent` directly through the repositories so
    /// a test can set up an already-nested tree before exercising
    /// `indentBlock`/`outdentBlock` against it.
    @discardableResult
    private func createItem(
        documentId: String,
        parentItemId: String? = nil,
        orderKey: String,
        textKind: String,
        text: String,
        documentItemRepository: DocumentItemRepository,
        textItemRepository: TextItemRepository
    ) throws -> DocumentItem {
        let item = try documentItemRepository.create(
            DocumentItem(documentId: documentId, parentItemId: parentItemId, contentType: "text", orderKey: orderKey)
        )
        _ = try textItemRepository.create(TextContent(itemId: item.id, textKind: textKind, plainText: text))
        return item
    }

    /// A minimal, non-`View` holder for a `@FocusState` property — just so
    /// tests can pass a real `FocusState<String?>.Binding` to a `chrome(...)`
    /// factory the same way `DetailScreen` does, without needing to mount an
    /// actual SwiftUI view hierarchy.
    private struct FocusStateHolder {
        @FocusState var focusedBlockId: String?
    }

    // MARK: - `*BlockView.chrome(...)` forwards `onIndent`/`onOutdent`

    @Test("BulletedListBlockView.chrome(...) forwards onIndent/onOutdent to the returned BlockRowChrome")
    func bulletedListChromeForwardsIndentOutdent() {
        var indentCalls = 0
        var outdentCalls = 0
        let holder = FocusStateHolder()
        var cursorOffsetToApply: Int?

        let chrome = BulletedListBlockView.chrome(
            item: DocumentItem(documentId: "doc", contentType: "text", orderKey: "a"),
            content: TextContent(itemId: "item", textKind: TextItemKind.bulletedListItem, plainText: "Item"),
            depth: 0,
            focusedBlockId: holder.$focusedBlockId,
            cursorOffsetToApply: Binding(get: { cursorOffsetToApply }, set: { cursorOffsetToApply = $0 }),
            onTextChange: { _ in },
            onEnter: { _, _ in },
            onBackspaceAtStart: { _ in },
            onIndent: { indentCalls += 1 },
            onOutdent: { outdentCalls += 1 }
        )

        chrome.onIndent?()
        chrome.onOutdent?()

        #expect(indentCalls == 1)
        #expect(outdentCalls == 1)
    }

    @Test("NumberedListBlockView.chrome(...) forwards onIndent/onOutdent to the returned BlockRowChrome")
    func numberedListChromeForwardsIndentOutdent() {
        var indentCalls = 0
        var outdentCalls = 0
        let holder = FocusStateHolder()
        var cursorOffsetToApply: Int?

        let chrome = NumberedListBlockView.chrome(
            item: DocumentItem(documentId: "doc", contentType: "text", orderKey: "a"),
            content: TextContent(itemId: "item", textKind: TextItemKind.numberedListItem, plainText: "Item"),
            numberedListNumber: 1,
            depth: 0,
            focusedBlockId: holder.$focusedBlockId,
            cursorOffsetToApply: Binding(get: { cursorOffsetToApply }, set: { cursorOffsetToApply = $0 }),
            onTextChange: { _ in },
            onEnter: { _, _ in },
            onBackspaceAtStart: { _ in },
            onIndent: { indentCalls += 1 },
            onOutdent: { outdentCalls += 1 }
        )

        chrome.onIndent?()
        chrome.onOutdent?()

        #expect(indentCalls == 1)
        #expect(outdentCalls == 1)
    }

    @Test("ChecklistBlockView.chrome(...) forwards onIndent/onOutdent to the returned BlockRowChrome")
    func checklistChromeForwardsIndentOutdent() {
        var indentCalls = 0
        var outdentCalls = 0
        let holder = FocusStateHolder()
        var cursorOffsetToApply: Int?

        let chrome = ChecklistBlockView.chrome(
            item: DocumentItem(documentId: "doc", contentType: "text", orderKey: "a"),
            content: TextContent(itemId: "item", textKind: TextItemKind.checklist, plainText: "Item"),
            depth: 0,
            focusedBlockId: holder.$focusedBlockId,
            cursorOffsetToApply: Binding(get: { cursorOffsetToApply }, set: { cursorOffsetToApply = $0 }),
            onTextChange: { _ in },
            onEnter: { _, _ in },
            onBackspaceAtStart: { _ in },
            onToggleChecklist: {},
            onIndent: { indentCalls += 1 },
            onOutdent: { outdentCalls += 1 }
        )

        chrome.onIndent?()
        chrome.onOutdent?()

        #expect(indentCalls == 1)
        #expect(outdentCalls == 1)
    }

    @Test("A non-list kind's chrome(...) has no onIndent/onOutdent parameter, so BlockRowChrome falls back to nil")
    func nonListChromeLeavesIndentOutdentNil() {
        let holder = FocusStateHolder()
        var cursorOffsetToApply: Int?

        let chrome = ParagraphBlockView.chrome(
            item: DocumentItem(documentId: "doc", contentType: "text", orderKey: "a"),
            content: TextContent(itemId: "item", textKind: TextItemKind.paragraph, plainText: "Item"),
            focusedBlockId: holder.$focusedBlockId,
            cursorOffsetToApply: Binding(get: { cursorOffsetToApply }, set: { cursorOffsetToApply = $0 }),
            onTextChange: { _ in },
            onEnter: { _, _ in },
            onBackspaceAtStart: { _ in }
        )

        #expect(chrome.onIndent == nil)
        #expect(chrome.onOutdent == nil)
    }

    // MARK: - `DetailViewModel.listNestingInfo(forItemId:)`
    //
    // `canOutdent`/`onDismissKeyboard` are no longer `chrome(...)`/
    // `BlockRowChrome` parameters — the on-screen keyboard toolbar is
    // configured independently, off `focusedBlockId`, by `DetailScreen
    // .configureAccessoryToolbar(forBlockId:)` (`AccessoryToolbarCoordinator`'s
    // doc comment explains why). That method no longer reads
    // `item.parentItemId` or checks list-kind membership itself — it asks
    // `DetailViewModel.listNestingInfo(forItemId:)` for both, so these
    // tests exercise that method directly rather than reproducing its
    // expression inline.

    @Test("listNestingInfo(forItemId:) reports canOutdent == false for a top-level list item")
    func listNestingInfoReportsCanOutdentFalseForTopLevelItem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let topLevelItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.bulletedListItem,
            text: "Top level", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        #expect(viewModel.listNestingInfo(forItemId: topLevelItem.id)?.canOutdent == false)
    }

    @Test("listNestingInfo(forItemId:) reports canOutdent == true for a nested list item")
    func listNestingInfoReportsCanOutdentTrueForNestedItem() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let parentItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.bulletedListItem,
            text: "Parent", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let nestedItem = try createItem(
            documentId: document.id, parentItemId: parentItem.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem,
            text: "Nested", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        #expect(viewModel.listNestingInfo(forItemId: nestedItem.id)?.canOutdent == true)
    }

    @Test("listNestingInfo(forItemId:) is nil for a non-list-kind block")
    func listNestingInfoIsNilForNonListKind() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let paragraphItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            text: "Just a paragraph", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        #expect(viewModel.listNestingInfo(forItemId: paragraphItem.id) == nil)
    }

    // MARK: - `DetailScreen.blockRow(for:content:)`'s closure literals, reproduced

    @Test("DetailScreen's onIndent closure ({ viewModel.indentBlock(item.id) }) indents exactly the focused item")
    func detailScreenStyleOnIndentClosureIndentsCorrectBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let firstItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.bulletedListItem,
            text: "First", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let secondItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(firstItem.orderKey, nil),
            textKind: TextItemKind.bulletedListItem,
            text: "Second", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // Exactly `DetailScreen.blockRow(for:content:)`'s own closure
        // literal for the bulleted-list case, built against `secondItem`
        // — the item the user has focused.
        let item = secondItem
        let onIndent: () -> Void = { viewModel.indentBlock(item.id) }

        onIndent()

        #expect(viewModel.items.first(where: { $0.id == secondItem.id })?.parentItemId == firstItem.id)
        // The other item is untouched — confirms the closure acted on the
        // right block id, not just any list item.
        #expect(viewModel.items.first(where: { $0.id == firstItem.id })?.parentItemId == nil)
    }

    @Test("DetailScreen's onOutdent closure ({ viewModel.outdentBlock(item.id) }) outdents exactly the focused item")
    func detailScreenStyleOnOutdentClosureOutdentsCorrectBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Diary"))
        let parentItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.bulletedListItem,
            text: "Parent", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let nestedItem = try createItem(
            documentId: document.id, parentItemId: parentItem.id, orderKey: OrderKey.between(nil, nil),
            textKind: TextItemKind.bulletedListItem,
            text: "Nested", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        #expect(viewModel.depth(forItemId: nestedItem.id) == 1)

        // Exactly `DetailScreen.blockRow(for:content:)`'s own closure
        // literal for the bulleted-list case, built against `nestedItem`.
        let item = nestedItem
        let onOutdent: () -> Void = { viewModel.outdentBlock(item.id) }

        onOutdent()

        #expect(viewModel.items.first(where: { $0.id == nestedItem.id })?.parentItemId == nil)
        #expect(viewModel.depth(forItemId: nestedItem.id) == 0)
    }
}
