import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import semibold

/// Tests for the `03-copy-action` brief — `DetailViewModel.copySelectionToClipboard(range:)`/
/// `.cutSelectionToClipboard(range:)`, called directly (no
/// `UIEditMenuInteraction`/menu UI involved at all, per AC1's own
/// parenthetical) against a throwaway in-memory database, the same way
/// `DetailViewModelTests` exercises every other editor action.
///
/// The main scenario below (`fullAndBoundaryBlocksSerializeCorrectly`)
/// reuses `CrossBlockSelection/README.md`'s own worked example verbatim —
/// a paragraph, then two bulleted list items sharing one `ListGroup`, with
/// the selection starting mid-word in the paragraph and ending mid-word in
/// the last list item — so this suite and the README stay checkable
/// against each other.
@MainActor
struct CrossBlockCopyActionTests {
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

    private func decodedPayload(from pasteboard: UIPasteboard) throws -> BlockClipboardPayload {
        let data = try #require(pasteboard.data(forPasteboardType: BlockClipboardPayload.utType.identifier))
        return try BlockClipboardPayload.decode(data)
    }

    private func plainTextRepresentation(from pasteboard: UIPasteboard) throws -> String {
        let data = try #require(pasteboard.data(forPasteboardType: UTType.plainText.identifier))
        return try #require(String(data: data, encoding: .utf8))
    }

    // MARK: - AC1/AC2/AC3/AC4 — README B1's worked example

    @Test(
        "Copy serializes the fully selected middle block intact and both boundary blocks text-trimmed, writing BlockClipboardPayload + a MarkdownExporter fallback into one pasteboard item"
    )
    func fullAndBoundaryBlocksSerializeCorrectly() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let group = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))

        let itemA = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Hello world", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemB = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemA.orderKey, nil), depth: 0, listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "item one",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemC = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemB.orderKey, nil), depth: 1, listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "item two",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // "world" (offset 6) in A through "item" (offset 4) in C.
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: itemA.id, offset: 6),
            end: DocumentTextLocation(blockId: itemC.id, offset: 4)
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockCopyActionTests.fullAndBoundary")
        defer { UIPasteboard.remove(withName: .init("CrossBlockCopyActionTests.fullAndBoundary")) }

        let write = try viewModel.copySelectionToClipboard(range: range, pasteboard: pasteboard)

        let textByItemId = Dictionary(uniqueKeysWithValues: write.payload.textContents.map { ($0.itemId, $0) })
        let itemsById = Dictionary(uniqueKeysWithValues: write.payload.items.map { ($0.id, $0) })

        // AC2 — boundary block A: only the selected substring, same kind.
        #expect(textByItemId[itemA.id]?.plainText == "world")
        #expect(textByItemId[itemA.id]?.textKind == TextItemKind.paragraph)

        // AC1 — fully selected block B: identical kind/style/text to the original.
        #expect(textByItemId[itemB.id]?.plainText == "item one")
        #expect(textByItemId[itemB.id]?.textKind == TextItemKind.bulletedListItem)
        #expect(itemsById[itemB.id]?.depth == 0)
        #expect(itemsById[itemB.id]?.listGroupId == group.id)

        // AC2 — boundary block C: only "item" kept, heading-level-style metadata
        // (here, list kind + depth) preserved even though the text is trimmed.
        #expect(textByItemId[itemC.id]?.plainText == "item")
        #expect(textByItemId[itemC.id]?.textKind == TextItemKind.bulletedListItem)
        #expect(itemsById[itemC.id]?.depth == 1)
        #expect(itemsById[itemC.id]?.listGroupId == group.id)

        // The shared ListGroup is carried over once, verbatim (same id).
        #expect(write.payload.listGroups.count == 1)
        #expect(write.payload.listGroups.first?.id == group.id)

        // AC3 — the payload round-trips through the pasteboard under the
        // app's own UTType.
        let decoded = try decodedPayload(from: pasteboard)
        #expect(decoded == write.payload)

        // AC4 — the same pasteboard item also carries a MarkdownExporter
        // Markdown fallback as its plain-text representation.
        let expectedMarkdown = MarkdownExporter.render(
            documentTitle: document.title,
            items: [itemA, itemB, itemC],
            textContents: [
                itemA.id: TextContent(itemId: itemA.id, textKind: TextItemKind.paragraph, plainText: "world"),
                itemB.id: TextContent(itemId: itemB.id, textKind: TextItemKind.bulletedListItem, plainText: "item one"),
                itemC.id: TextContent(itemId: itemC.id, textKind: TextItemKind.bulletedListItem, plainText: "item")
            ]
        )
        #expect(write.markdown == expectedMarkdown)
        #expect(try plainTextRepresentation(from: pasteboard) == expectedMarkdown)
    }

    // MARK: - AC5 / README B2 — a selection covering only part of a list group

    @Test("Copy doesn't reassign or touch listGroupId when only one member of a shared list group is selected")
    func partialListGroupSelectionDoesNotReassignListGroupId() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "List"))
        let group = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))

        let itemX = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "x",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemY = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemX.orderKey, nil), listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "y",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemZ = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemY.orderKey, nil), listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "z",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // Only the middle item (Y) of the three-member group is selected.
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: itemY.id, offset: 0),
            end: DocumentTextLocation(blockId: itemY.id, offset: 1)
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockCopyActionTests.partialGroup")
        defer { UIPasteboard.remove(withName: .init("CrossBlockCopyActionTests.partialGroup")) }

        let write = try viewModel.copySelectionToClipboard(range: range, pasteboard: pasteboard)

        // Only Y is in the copy — X and Z weren't touched by the selection at all.
        #expect(write.payload.items.map(\.id) == [itemY.id])
        #expect(write.payload.items.first?.listGroupId == group.id)

        // The group itself is carried over once, with the exact same id —
        // no reassignment/merge happens at copy time.
        #expect(write.payload.listGroups.count == 1)
        #expect(write.payload.listGroups.first?.id == group.id)

        // The source document's own group membership is untouched by the copy.
        #expect(try documentItemRepository.find(id: itemX.id)?.listGroupId == group.id)
        #expect(try documentItemRepository.find(id: itemY.id)?.listGroupId == group.id)
        #expect(try documentItemRepository.find(id: itemZ.id)?.listGroupId == group.id)
    }

    // MARK: - AC6 — Cut

    @Test("Cut copies the same content as Copy, then fully deletes the selected block and trims the two boundary blocks, leaving the rest of the document untouched")
    func cutCopiesThenDeletesOrTrimsSelectedBlocks() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let group = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))

        let itemA = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Hello world", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemB = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemA.orderKey, nil), depth: 0, listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "item one",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemC = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemB.orderKey, nil), depth: 1, listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "item two",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemD = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemC.orderKey, nil), textKind: TextItemKind.paragraph,
            plainText: "Untouched", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: itemA.id, offset: 6),
            end: DocumentTextLocation(blockId: itemC.id, offset: 4)
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockCopyActionTests.cut")
        defer { UIPasteboard.remove(withName: .init("CrossBlockCopyActionTests.cut")) }

        let write = try viewModel.cutSelectionToClipboard(range: range, pasteboard: pasteboard)

        // Clipboard content is identical to what a plain copy of the same
        // range would have produced.
        let textByItemId = Dictionary(uniqueKeysWithValues: write.payload.textContents.map { ($0.itemId, $0) })
        #expect(textByItemId[itemA.id]?.plainText == "world")
        #expect(textByItemId[itemB.id]?.plainText == "item one")
        #expect(textByItemId[itemC.id]?.plainText == "item")

        // The fully selected block (B) is gone from the in-memory document…
        #expect(viewModel.items.map(\.id) == [itemA.id, itemC.id, itemD.id])
        // …and actually removed from storage, not just hidden in memory.
        #expect(try documentItemRepository.allItems(documentId: document.id).map(\.id) == [itemA.id, itemC.id, itemD.id])

        // The two boundary blocks keep their own id/kind, with only the
        // selected character range removed and the remaining text kept.
        #expect(viewModel.textContent(forItemId: itemA.id).plainText == "Hello ")
        #expect(viewModel.textContent(forItemId: itemA.id).textKind == TextItemKind.paragraph)
        #expect(viewModel.textContent(forItemId: itemC.id).plainText == " two")
        #expect(viewModel.textContent(forItemId: itemC.id).textKind == TextItemKind.bulletedListItem)
        #expect(viewModel.depth(forItemId: itemC.id) == 1)

        // C is still a live member of the group (it wasn't deleted), so the
        // group itself must still exist.
        #expect(try listGroupRepository.find(id: group.id) != nil)

        // The untouched block outside the selection is exactly as it was.
        #expect(viewModel.textContent(forItemId: itemD.id).plainText == "Untouched")

        // Persisted storage agrees with the in-memory state for the trimmed
        // boundary blocks too.
        #expect(try textItemRepository.find(itemId: itemA.id)?.plainText == "Hello ")
        #expect(try textItemRepository.find(itemId: itemC.id)?.plainText == " two")
    }

    @Test("Cut hard-deletes a list group once every one of its members has been fully cut away")
    func cutRemovesOrphanedListGroup() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let listGroupRepository = ListGroupRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "List"))
        let group = try listGroupRepository.create(ListGroup(documentId: document.id, listType: TextItemKind.bulletedListItem))

        let item1 = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "aaa", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let item2 = try createItem(
            documentId: document.id, orderKey: OrderKey.between(item1.orderKey, nil), listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "x",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let item3 = try createItem(
            documentId: document.id, orderKey: OrderKey.between(item2.orderKey, nil), listGroupId: group.id,
            textKind: TextItemKind.bulletedListItem, plainText: "y",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let item4 = try createItem(
            documentId: document.id, orderKey: OrderKey.between(item3.orderKey, nil), textKind: TextItemKind.paragraph,
            plainText: "zzz", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // Both group members (item2/item3) sit strictly between the
        // selection's start (end of item1's text) and end (start of
        // item4's text), so they're fully selected while item1/item4 stay
        // untouched (zero-length boundary selections at their very edges).
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: item1.id, offset: 3),
            end: DocumentTextLocation(blockId: item4.id, offset: 0)
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockCopyActionTests.orphan")
        defer { UIPasteboard.remove(withName: .init("CrossBlockCopyActionTests.orphan")) }

        try viewModel.cutSelectionToClipboard(range: range, pasteboard: pasteboard)

        #expect(viewModel.items.map(\.id) == [item1.id, item4.id])
        #expect(viewModel.textContent(forItemId: item1.id).plainText == "aaa")
        #expect(viewModel.textContent(forItemId: item4.id).plainText == "zzz")
        #expect(try listGroupRepository.find(id: group.id) == nil)
    }
}
