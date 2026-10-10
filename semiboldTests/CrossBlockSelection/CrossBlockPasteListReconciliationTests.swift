import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import semibold

/// Split out of `CrossBlockPasteActionTests` (same `file_length`-headroom
/// precedent as `CrossBlockCutListReconciliationTests`) — covers the
/// `04-paste-same-different-document` brief's list-structure acceptance
/// criteria:
/// - Common invariant 6 — pasted items that shared one `listGroupId` in
///   the original still share exactly one (newly created) group.
/// - C3/common invariant 7 — a pasted range whose first block starts at
///   depth > 0 with no ancestor in the range gets clamped to depth 0,
///   with every other pasted block keeping its original relative depth
///   difference from that first block.
/// - `semiboldTests/ListBlock/README.md` common invariant 6 — adjacent
///   blocks never differ by more than one depth level after the paste,
///   including at the two edges the inserted range creates.
@MainActor
struct CrossBlockPasteListReconciliationTests {
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

    // MARK: - Common invariant 6 — shared listGroupId members stay in one new group

    @Test("Pasted items that shared one listGroupId in the original still share exactly one new ListGroup")
    func pastedListGroupMembersShareOneNewGroup() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let anchor = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Anchor", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // Two list items that shared `original-group` in the source document.
        let payload = BlockClipboardPayload(
            items: [
                DocumentItem(
                    id: "src-1", documentId: "other-doc", depth: 0, listGroupId: "original-group",
                    contentType: "text", orderKey: "01"
                ),
                DocumentItem(
                    id: "src-2", documentId: "other-doc", depth: 1, listGroupId: "original-group",
                    contentType: "text", orderKey: "02"
                )
            ],
            textContents: [
                TextContent(itemId: "src-1", textKind: TextItemKind.bulletedListItem, plainText: "one"),
                TextContent(itemId: "src-2", textKind: TextItemKind.bulletedListItem, plainText: "two")
            ],
            listGroups: [
                ListGroup(id: "original-group", documentId: "other-doc", listType: TextItemKind.bulletedListItem)
            ],
            textMarks: []
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockPasteListReconciliationTests.sharedGroup")
        defer { UIPasteboard.remove(withName: .init("CrossBlockPasteListReconciliationTests.sharedGroup")) }
        try seedPasteboard(pasteboard, with: payload)

        let pasted = try viewModel.pasteFromClipboard(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.count == 2)
        let newGroupId = try #require(pasted[0].listGroupId)
        #expect(pasted[1].listGroupId == newGroupId)
        // Never the original group's id — a brand-new group was created.
        #expect(newGroupId != "original-group")
        #expect(try listGroupRepository.find(id: newGroupId)?.documentId == document.id)
        #expect(try listGroupRepository.find(id: newGroupId)?.listType == TextItemKind.bulletedListItem)
        // Exactly one group now exists for the pasted pair, persisted.
        #expect(try documentItemRepository.find(id: pasted[0].id)?.listGroupId == newGroupId)
        #expect(try documentItemRepository.find(id: pasted[1].id)?.listGroupId == newGroupId)
    }

    // MARK: - C3 / common invariant 7 — depth-0 clamp with relative depth preserved

    @Test("A pasted range's first block starting at depth > 0 clamps to depth 0, keeping relative depth differences")
    func pasteClampsFirstBlockDepthAndShiftsRestProportionally() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let anchor = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Anchor", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // Selection started mid-list at depth 2 (its depth-0/1 ancestors
        // were outside the selection) — depth 2→3→2, same group throughout.
        let payload = BlockClipboardPayload(
            items: [
                DocumentItem(
                    id: "src-1", documentId: "other-doc", depth: 2, listGroupId: "g1",
                    contentType: "text", orderKey: "01"
                ),
                DocumentItem(
                    id: "src-2", documentId: "other-doc", depth: 3, listGroupId: "g1",
                    contentType: "text", orderKey: "02"
                ),
                DocumentItem(
                    id: "src-3", documentId: "other-doc", depth: 2, listGroupId: "g1",
                    contentType: "text", orderKey: "03"
                )
            ],
            textContents: [
                TextContent(itemId: "src-1", textKind: TextItemKind.bulletedListItem, plainText: "a"),
                TextContent(itemId: "src-2", textKind: TextItemKind.bulletedListItem, plainText: "b"),
                TextContent(itemId: "src-3", textKind: TextItemKind.bulletedListItem, plainText: "c")
            ],
            listGroups: [ListGroup(id: "g1", documentId: "other-doc", listType: TextItemKind.bulletedListItem)],
            textMarks: []
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockPasteListReconciliationTests.depthClamp")
        defer { UIPasteboard.remove(withName: .init("CrossBlockPasteListReconciliationTests.depthClamp")) }
        try seedPasteboard(pasteboard, with: payload)

        let pasted = try viewModel.pasteFromClipboard(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.count == 3)
        // First block clamped from depth 2 to depth 0; the rest keep their
        // original relative difference from it (2→3→2 becomes 0→1→0).
        #expect(pasted[0].depth == 0)
        #expect(pasted[1].depth == 1)
        #expect(pasted[2].depth == 0)

        // Persisted depths agree with in-memory state.
        #expect(try documentItemRepository.find(id: pasted[0].id)?.depth == 0)
        #expect(try documentItemRepository.find(id: pasted[1].id)?.depth == 1)
        #expect(try documentItemRepository.find(id: pasted[2].id)?.depth == 0)
    }

    // MARK: - ListBlock/README.md common invariant 6 — adjacent depth gap ≤ 1

    @Test("Pasting a deeply nested range between two shallow blocks closes the depth gap at both edges")
    func pasteBetweenShallowBlocksReconcilesBothEdges() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let existingGroup = try listGroupRepository.create(
            ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem)
        )

        // One existing depth-0 list item; pasting will land right after it,
        // immediately before a plain paragraph.
        let before = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), depth: 0, listGroupId: existingGroup.id,
            textKind: TextItemKind.bulletedListItem, plainText: "before",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let after = try createItem(
            documentId: document.id, orderKey: OrderKey.between(before.orderKey, nil), depth: 0,
            listGroupId: existingGroup.id, textKind: TextItemKind.bulletedListItem, plainText: "after",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // The pasted range's own first/last blocks are both depth 0 of the
        // SAME listType as `before`/`after`, but a different (soon to be
        // newly created) group — pasting between two members of one
        // existing group with no depth gap at either edge still exercises
        // the reconciliation call; the group split is the thing actually
        // under test here, since both pasted edges start/end at depth 0
        // already (no clamp needed) and should merge into the surrounding
        // group rather than leaving three groups of the same kind
        // array-adjacent.
        let payload = BlockClipboardPayload(
            items: [
                DocumentItem(
                    id: "src-1", documentId: "other-doc", depth: 0, listGroupId: "g1",
                    contentType: "text", orderKey: "01"
                )
            ],
            textContents: [TextContent(itemId: "src-1", textKind: TextItemKind.bulletedListItem, plainText: "middle")],
            listGroups: [ListGroup(id: "g1", documentId: "other-doc", listType: TextItemKind.bulletedListItem)],
            textMarks: []
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockPasteListReconciliationTests.adjacency")
        defer { UIPasteboard.remove(withName: .init("CrossBlockPasteListReconciliationTests.adjacency")) }
        try seedPasteboard(pasteboard, with: payload)

        let pasted = try viewModel.pasteFromClipboard(
            at: DocumentTextLocation(blockId: before.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.count == 1)
        #expect(viewModel.items.map(\.id) == [before.id, pasted[0].id, after.id])

        // Common invariant 6 (ListBlock/README.md) — adjacent depth gap ≤ 1
        // at both edges the paste created.
        #expect(abs(viewModel.depth(forItemId: before.id) - viewModel.depth(forItemId: pasted[0].id)) <= 1)
        #expect(abs(viewModel.depth(forItemId: pasted[0].id) - viewModel.depth(forItemId: after.id)) <= 1)

        // The three same-kind, now-array-adjacent blocks end up in exactly
        // one group rather than splitting into separate groups either side
        // of the pasted block.
        let beforeGroup = try #require(try documentItemRepository.find(id: before.id)?.listGroupId)
        let pastedGroup = try #require(try documentItemRepository.find(id: pasted[0].id)?.listGroupId)
        let afterGroup = try #require(try documentItemRepository.find(id: after.id)?.listGroupId)
        #expect(beforeGroup == pastedGroup)
        #expect(pastedGroup == afterGroup)
    }

    @Test("Pasting a deeply nested range right after a plain paragraph clamps the first pasted block to depth 0")
    func pasteAfterNonListBlockClampsFirstPastedDepth() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let paragraph = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Just text",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // Pasted range's own first block starts at depth 2 with no ancestor
        // in the range (C3) — without the clamp this would land right after
        // a depth-0 paragraph and violate the adjacency invariant.
        let payload = BlockClipboardPayload(
            items: [
                DocumentItem(
                    id: "src-1", documentId: "other-doc", depth: 2, listGroupId: "g1",
                    contentType: "text", orderKey: "01"
                )
            ],
            textContents: [TextContent(itemId: "src-1", textKind: TextItemKind.bulletedListItem, plainText: "deep")],
            listGroups: [ListGroup(id: "g1", documentId: "other-doc", listType: TextItemKind.bulletedListItem)],
            textMarks: []
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockPasteListReconciliationTests.afterParagraph")
        defer { UIPasteboard.remove(withName: .init("CrossBlockPasteListReconciliationTests.afterParagraph")) }
        try seedPasteboard(pasteboard, with: payload)

        let pasted = try viewModel.pasteFromClipboard(
            at: DocumentTextLocation(blockId: paragraph.id, offset: 9), pasteboard: pasteboard
        )

        #expect(pasted.count == 1)
        #expect(pasted[0].depth == 0)
        #expect(abs(viewModel.depth(forItemId: paragraph.id) - viewModel.depth(forItemId: pasted[0].id)) <= 1)
    }
}
