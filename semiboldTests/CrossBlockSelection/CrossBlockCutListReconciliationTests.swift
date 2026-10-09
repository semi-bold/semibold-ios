import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import semibold

/// Split out of `CrossBlockCopyActionTests` (which SwiftLint's `file_length`
/// started flagging once these two were added) — regression coverage added
/// during review of the `03-copy-action` brief's Cut AC, covering two gaps
/// the original commit (`194ce92`) left untested:
/// - `deleteSelectedRange` reconciling newly-adjacent list blocks after a
///   cut removes a run of fully selected interior blocks
///   (`semiboldTests/ListBlock/README.md` common invariant 6).
/// - `CrossBlockSelectionClipboardSerializer`'s `TextMark`-clipping rule for
///   a boundary block.
@MainActor
struct CrossBlockCutListReconciliationTests {
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

    /// A throwaway, uniquely-named pasteboard per test — never
    /// `UIPasteboard.general` — matching `BlockClipboardPayloadTests`'
    /// precedent so a test run never touches the host device/simulator's
    /// real clipboard.
    private func makeTestPasteboard(name: String) -> UIPasteboard {
        guard let pasteboard = UIPasteboard(name: .init(name), create: true) else {
            Issue.record("Could not create a throwaway test pasteboard")
            return .general
        }
        return pasteboard
    }

    @discardableResult
    private func createItem(
        documentId: String,
        orderKey: String,
        depth: Int = 0,
        listGroupId: String? = nil,
        textKind: String,
        plainText: String,
        documentItemRepository: DocumentItemRepository,
        textItemRepository: TextItemRepository
    ) throws -> DocumentItem {
        let item = try documentItemRepository.create(
            DocumentItem(documentId: documentId, depth: depth, listGroupId: listGroupId, contentType: "text", orderKey: orderKey)
        )
        _ = try textItemRepository.create(TextContent(itemId: item.id, textKind: textKind, plainText: plainText))
        return item
    }

    // MARK: - Depth reconciliation for newly adjacent blocks after a cut

    @Test("Cut across depth 0→1→2→3→2 reconciles newly-adjacent blocks (ListBlock/README.md invariant 6)")
    func cutAcrossNestedListReconcilesNewlyAdjacentDepths() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Nested"))
        let group = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))

        // A valid nested list going into the cut — every array-adjacent
        // pair differs by at most one depth level (0→1→2→3→2).
        let nodeA = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), depth: 0, listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "zero",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let nodeB = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nodeA.orderKey, nil), depth: 1, listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "one",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let nodeC = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nodeB.orderKey, nil), depth: 2, listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "two",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let nodeD = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nodeC.orderKey, nil), depth: 3, listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "three",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let nodeE = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nodeD.orderKey, nil), depth: 2, listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "four",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // Boundary blocks are nodeA/nodeE themselves (trimmed, not removed);
        // nodeB-nodeD sit strictly between them in the selection, so they're
        // fully selected and removed outright — the reviewer's exact repro.
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: nodeA.id, offset: 2),
            end: DocumentTextLocation(blockId: nodeE.id, offset: 2)
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockCutListReconciliationTests.nestedListDepthGap")
        defer { UIPasteboard.remove(withName: .init("CrossBlockCutListReconciliationTests.nestedListDepthGap")) }

        try viewModel.cutSelectionToClipboard(range: range, pasteboard: pasteboard)

        // nodeB/nodeC/nodeD are gone; nodeA/nodeE are now array-adjacent.
        #expect(viewModel.items.map(\.id) == [nodeA.id, nodeE.id])
        #expect(viewModel.textContent(forItemId: nodeA.id).plainText == "ze")
        #expect(viewModel.textContent(forItemId: nodeE.id).plainText == "ur")

        // Both were already in the same group, so no group merge is
        // needed — but the depth gap (0 vs 2) must still be closed.
        // `reconcileAdjacentListBlocks` clamps the lower block (and any
        // descendants, none here) down to upper depth + 1 — the exact same
        // clamp `mergeOrDeleteBlock`'s C3 path already performs for a
        // single-block delete (see
        // `ListBlockLifecycleTests.c3_backspaceRemovingListItemCascadesDescendantDepth`).
        #expect(viewModel.depth(forItemId: nodeA.id) == 0)
        #expect(viewModel.depth(forItemId: nodeE.id) == 1)

        // Common invariant 6 — adjacent blocks differ by at most one depth level.
        #expect(abs(viewModel.depth(forItemId: nodeE.id) - viewModel.depth(forItemId: nodeA.id)) <= 1)

        // Still one live group containing both survivors — persisted, not
        // just in-memory.
        #expect(try listGroupRepository.find(id: group.id) != nil)
        #expect(try documentItemRepository.find(id: nodeA.id)?.listGroupId == group.id)
        #expect(try documentItemRepository.find(id: nodeE.id)?.listGroupId == group.id)
        #expect(try documentItemRepository.find(id: nodeE.id)?.depth == 1)
    }

    // MARK: - TextMark clipping coverage for a boundary block

    @Test("Copy clips a boundary block's TextMarks: inside rebased, straddling trimmed, outside dropped")
    func copyClipsBoundaryBlockTextMarksToSelectedRange() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let textMarkRepository = TextMarkRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Marks"))

        let itemA = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Hello world", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemB = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemA.orderKey, nil), textKind: TextItemKind.paragraph,
            plainText: "Second block", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        // itemA's text is "Hello world" (indices 0-11); the selection below
        // starts at offset 6, so itemA's selected range is [6, 11) ("world").
        let markOutside = try textMarkRepository.create(
            TextMark(itemId: itemA.id, startOffset: 0, endOffset: 4, markType: "bold")
        )
        let markStraddling = try textMarkRepository.create(
            TextMark(itemId: itemA.id, startOffset: 3, endOffset: 8, markType: "italic")
        )
        let markInside = try textMarkRepository.create(
            TextMark(itemId: itemA.id, startOffset: 6, endOffset: 11, markType: "underline")
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: itemA.id, offset: 6),
            end: DocumentTextLocation(blockId: itemB.id, offset: 0)
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockCutListReconciliationTests.markClipping")
        defer { UIPasteboard.remove(withName: .init("CrossBlockCutListReconciliationTests.markClipping")) }

        let write = try viewModel.copySelectionToClipboard(range: range, pasteboard: pasteboard)
        let marksByType = Dictionary(uniqueKeysWithValues: write.payload.textMarks.map { ($0.markType, $0) })

        // Fully outside the selected range [6, 11) — dropped entirely, not
        // just left unclipped.
        #expect(marksByType["bold"] == nil)
        #expect(write.payload.textMarks.contains { $0.id == markOutside.id } == false)

        // Straddles the boundary at offset 6 — clipped to only the
        // overlapping portion of the original range ([6, 8) of [3, 8)),
        // rebased to start at 0 ([0, 2)).
        let straddlingResult = try #require(marksByType["italic"])
        #expect(straddlingResult.id == markStraddling.id)
        #expect(straddlingResult.startOffset == 0)
        #expect(straddlingResult.endOffset == 2)

        // Entirely inside the selected range — kept whole, rebased to
        // start at 0 ([6, 11) of the original becomes [0, 5)).
        let insideResult = try #require(marksByType["underline"])
        #expect(insideResult.id == markInside.id)
        #expect(insideResult.startOffset == 0)
        #expect(insideResult.endOffset == 5)
    }
}
