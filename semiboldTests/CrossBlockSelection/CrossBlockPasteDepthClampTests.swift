import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import semibold

/// Split out of `CrossBlockPasteListReconciliationTests` (same
/// `file_length`/`type_body_length`-headroom precedent as that file's own
/// split from `CrossBlockPasteActionTests`) — a regression gap found on
/// code review of the `04-paste-same-different-document` brief's commit
/// (`cde6850`): `reconcilePasteEdges` calls `reconcileAdjacentListBlocks`
/// at BOTH edges of a paste, but no existing test actually forced the
/// numeric depth-clamp branch (as opposed to the group-merge branch) to
/// fire.
///
/// The LEADING edge (before-block ↔ pasted-first) can never need the
/// clamp, because `CrossBlockSelectionPasteRewriter` always forces the
/// pasted range's first block to depth 0 — `0 > upperDepth + 1` is never
/// true for `upperDepth >= 0`. Only the TRAILING edge (pasted-last ↔ the
/// pre-existing block right after the paste) can realistically need it,
/// when that pre-existing block is more deeply nested than the pasted
/// range's own last block allows. This file proves that branch fires with
/// the same clamp math `CrossBlockCutListReconciliationTests
/// .cutAcrossNestedListReconcilesNewlyAdjacentDepths` already verifies for
/// the cut side.
@MainActor
struct CrossBlockPasteDepthClampTests {
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
            DocumentItem(
                documentId: documentId, depth: depth, listGroupId: listGroupId, contentType: "text", orderKey: orderKey
            )
        )
        _ = try textItemRepository.create(TextContent(itemId: item.id, textKind: textKind, plainText: plainText))
        return item
    }

    private func seedPasteboard(_ pasteboard: UIPasteboard, with payload: BlockClipboardPayload) throws {
        let data = try BlockClipboardPayload.encode(
            items: payload.items,
            textContents: payload.textContents,
            listGroups: payload.listGroups,
            textMarks: payload.textMarks
        )
        pasteboard.items = [[BlockClipboardPayload.utType.identifier: data]]
    }

    // MARK: - ListBlock/README.md common invariant 6 — trailing-edge numeric depth clamp

    @Test("Pasting a shallow range right before a deeply nested block clamps the pre-existing block's depth down")
    func pasteBeforeDeeplyNestedBlockClampsTrailingEdgeDepth() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        // A pre-existing, ungrouped block sitting at depth 3 — the paste
        // below will land immediately before it. Left without a
        // `listGroupId` of its own so this test isolates the numeric
        // depth clamp from the (separately covered) group-merge behavior.
        let after = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), depth: 3, listGroupId: nil,
            textKind: TextItemKind.bulletedListItem, plainText: "after",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // Pasted range ends (its own last block) at depth 1 — same
        // listType as `after`. `offset: 0` on `after` inserts the whole
        // range immediately before it, so there's no block before the
        // paste at all (the LEADING edge of `reconcilePasteEdges` is
        // skipped — `insertIndex == 0`) and only the TRAILING edge
        // (pasted-last ↔ `after`) is reconciled. Without that
        // reconciliation, `after` (depth 3) would sit 2 levels deeper than
        // the pasted range's last block (depth 1) — the depth-clamp branch
        // `reconcileAdjacentListBlocks` only takes on its trailing edge.
        let payload = BlockClipboardPayload(
            items: [
                DocumentItem(
                    id: "src-1", documentId: "other-doc", depth: 0, listGroupId: "g1",
                    contentType: "text", orderKey: "01"
                ),
                DocumentItem(
                    id: "src-2", documentId: "other-doc", depth: 1, listGroupId: "g1",
                    contentType: "text", orderKey: "02"
                )
            ],
            textContents: [
                TextContent(itemId: "src-1", textKind: TextItemKind.bulletedListItem, plainText: "shallow"),
                TextContent(itemId: "src-2", textKind: TextItemKind.bulletedListItem, plainText: "deeper")
            ],
            listGroups: [ListGroup(id: "g1", documentId: "other-doc", listType: TextItemKind.bulletedListItem)],
            textMarks: []
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockPasteDepthClampTests.trailingEdgeClamp")
        defer {
            UIPasteboard.remove(withName: .init("CrossBlockPasteDepthClampTests.trailingEdgeClamp"))
        }
        try seedPasteboard(pasteboard, with: payload)

        let pasted = try viewModel.pasteFromClipboard(
            at: DocumentTextLocation(blockId: after.id, offset: 0), pasteboard: pasteboard
        )

        #expect(pasted.count == 2)
        #expect(viewModel.items.map(\.id) == [pasted[0].id, pasted[1].id, after.id])

        // Pasted range's own depths are unaffected by the trailing-edge
        // reconciliation — only `after` moves.
        #expect(pasted[0].depth == 0)
        #expect(pasted[1].depth == 1)

        // `after` was depth 3; `reconcileAdjacentListBlocks` clamps it down
        // to exactly the pasted range's last block's depth + 1 (1 + 1 = 2),
        // the same `lowerDepth - (upperDepth + 1)` shift the cut-side test
        // already verifies.
        #expect(viewModel.depth(forItemId: after.id) == 2)
        #expect(abs(viewModel.depth(forItemId: pasted[1].id) - viewModel.depth(forItemId: after.id)) <= 1)

        // Persisted, not just in-memory.
        #expect(try documentItemRepository.find(id: after.id)?.depth == 2)
    }
}
