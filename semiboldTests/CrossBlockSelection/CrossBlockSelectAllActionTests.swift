import Foundation
import Testing

@testable import semibold

/// Tests for the `03-copy-action` brief's last Acceptance Criterion —
/// `DetailViewModel.selectAllBlocks(in:)`. Split into its own file
/// following the same `file_length` precedent as
/// `CrossBlockCutListReconciliationTests`.
@MainActor
struct CrossBlockSelectAllActionTests {
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

    @discardableResult
    private func createItem(
        documentId: String,
        orderKey: String,
        textKind: String,
        plainText: String,
        documentItemRepository: DocumentItemRepository,
        textItemRepository: TextItemRepository
    ) throws -> DocumentItem {
        let item = try documentItemRepository.create(
            DocumentItem(documentId: documentId, depth: 0, listGroupId: nil, contentType: "text", orderKey: orderKey)
        )
        _ = try textItemRepository.create(TextContent(itemId: item.id, textKind: textKind, plainText: plainText))
        return item
    }

    @Test("Select All spans from the first block's start to the last block's end")
    func selectAllSpansFirstToLastBlock() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let itemA = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Hello", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemB = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemA.orderKey, nil), textKind: TextItemKind.paragraph,
            plainText: "world", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemC = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemB.orderKey, nil), textKind: TextItemKind.paragraph,
            plainText: "!!!", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let tracker = CrossBlockSelectionTracker()

        viewModel.selectAllBlocks(in: tracker)

        #expect(tracker.isActive)
        #expect(tracker.anchor == DocumentTextLocation(blockId: itemA.id, offset: 0))
        #expect(tracker.current == DocumentTextLocation(blockId: itemC.id, offset: 3))

        let order = BlockOrder(blockIds: viewModel.items.map(\.id))
        let range = try #require(tracker.range(order: order))
        #expect(range.start == DocumentTextLocation(blockId: itemA.id, offset: 0))
        #expect(range.end == DocumentTextLocation(blockId: itemC.id, offset: 3))

        // itemA/itemC are this range's `start`/`end` — "경계 블록" by this
        // codebase's own terminology (`isFullySelected` is `false` for
        // them even when, as here, their whole text is what's selected).
        // itemB sits strictly between them, so it's the one "전체 선택
        // 블록" in this range.
        #expect(range.isFullySelected(blockId: itemA.id, order: order) == false)
        #expect(range.isFullySelected(blockId: itemB.id, order: order))
        #expect(range.isFullySelected(blockId: itemC.id, order: order) == false)

        // Every block's own selected sub-range still covers its whole text.
        #expect(range.selectedRange(blockId: itemA.id, textLength: 5, order: order) == NSRange(location: 0, length: 5))
        #expect(range.selectedRange(blockId: itemB.id, textLength: 5, order: order) == NSRange(location: 0, length: 5))
        #expect(range.selectedRange(blockId: itemC.id, textLength: 3, order: order) == NSRange(location: 0, length: 3))
    }

    @Test("Select All on a single-block document selects that block's whole text")
    func selectAllOnSingleBlockDocument() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Solo"))
        let onlyItem = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "alone", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()
        let tracker = CrossBlockSelectionTracker()

        viewModel.selectAllBlocks(in: tracker)

        #expect(tracker.anchor == DocumentTextLocation(blockId: onlyItem.id, offset: 0))
        #expect(tracker.current == DocumentTextLocation(blockId: onlyItem.id, offset: 5))
    }

    @Test("Select All with no blocks loaded is a no-op — no anchor is set")
    func selectAllOnEmptyDocumentIsNoOp() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let document = try documentRepository.create(Document(title: "Empty"))

        let viewModel = makeViewModel(document: document, store: store)
        // Deliberately NOT calling `viewModel.load()` here: `load()` always
        // self-heals a brand-new, zero-item document by creating one empty
        // paragraph (`DetailViewModel.createFirstItem()`), so `items` is
        // never actually empty after a normal load — this guard in
        // `selectAllBlocks` is defensive for a state the view model doesn't
        // reach in practice. Exercising it directly (pre-`load()`, `items`
        // still its freshly-initialized `[]`) is the only way to cover it.
        let tracker = CrossBlockSelectionTracker()

        viewModel.selectAllBlocks(in: tracker)

        #expect(tracker.isActive == false)
        #expect(tracker.anchor == nil)
        #expect(tracker.current == nil)
    }
}
