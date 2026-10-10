import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import semibold

/// Tests for the `04-paste-same-different-document` brief —
/// `DetailViewModel.pasteFromClipboard(at:pasteboard:)`, called directly
/// (no `UIEditMenuInteraction`/menu UI involved, same convention as copy/
/// cut). Covers README C1 (same-document paste), C2 (cross-document
/// paste), and common invariant 5 (every pasted block gets a fresh id).
/// Invariant 6 (shared `listGroupId`)/C3-invariant 7 (depth clamp)/the
/// `ListBlock/README.md` adjacency invariant live in
/// `CrossBlockPasteListReconciliationTests.swift` — split out up front so
/// this file stays well under SwiftLint's `file_length` warning even with
/// this brief's full six-AC scope.
@MainActor
struct CrossBlockPasteActionTests {
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
    /// `UIPasteboard.general`, same precedent as `CrossBlockCopyActionTests`.
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

    /// Writes `payload` straight into `pasteboard` under this app's own
    /// UTType, the same shape `copySelectionToClipboard` would have
    /// produced — lets a paste-only test seed the clipboard directly
    /// instead of running a full copy first.
    private func seedPasteboard(_ pasteboard: UIPasteboard, with payload: BlockClipboardPayload) throws {
        let data = try BlockClipboardPayload.encode(
            items: payload.items,
            textContents: payload.textContents,
            listGroups: payload.listGroups,
            textMarks: payload.textMarks
        )
        pasteboard.items = [[BlockClipboardPayload.utType.identifier: data]]
    }

    // MARK: - C1 — same-document paste

    @Test("Pasting into the same document decodes the payload, inserts it after the anchor block, documentId unchanged")
    func sameDocumentPasteInsertsDecodedBlocks() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let itemA = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "First", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemB = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemA.orderKey, nil), textKind: TextItemKind.paragraph,
            plainText: "Last", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        let payload = BlockClipboardPayload(
            items: [DocumentItem(id: "src-1", documentId: document.id, contentType: "text", orderKey: "01")],
            textContents: [TextContent(itemId: "src-1", textKind: TextItemKind.paragraph, plainText: "Pasted")],
            listGroups: [],
            textMarks: []
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockPasteActionTests.sameDocument")
        defer { UIPasteboard.remove(withName: .init("CrossBlockPasteActionTests.sameDocument")) }
        try seedPasteboard(pasteboard, with: payload)

        let pasted = try viewModel.pasteFromClipboard(
            at: DocumentTextLocation(blockId: itemA.id, offset: 5), pasteboard: pasteboard
        )

        #expect(pasted.count == 1)
        #expect(viewModel.items.map(\.id) == [itemA.id, pasted[0].id, itemB.id])
        #expect(viewModel.textContent(forItemId: pasted[0].id).plainText == "Pasted")
        #expect(pasted[0].documentId == document.id)

        // Persisted, not just in-memory.
        #expect(try documentItemRepository.find(id: pasted[0].id)?.documentId == document.id)
        #expect(try textItemRepository.find(itemId: pasted[0].id)?.plainText == "Pasted")
    }

    // MARK: - C2 — cross-document paste

    @Test("Pasting into a different document rewrites documentId to the target document on every pasted item")
    func crossDocumentPasteRewritesDocumentId() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let sourceDocument = try documentRepository.create(Document(title: "Source"))
        let sourceItem = try createItem(
            documentId: sourceDocument.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Copied text",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let sourceViewModel = makeViewModel(document: sourceDocument, store: store)
        sourceViewModel.load()
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: sourceItem.id, offset: 0),
            end: DocumentTextLocation(blockId: sourceItem.id, offset: 11)
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockPasteActionTests.crossDocument")
        defer { UIPasteboard.remove(withName: .init("CrossBlockPasteActionTests.crossDocument")) }
        try sourceViewModel.copySelectionToClipboard(range: range, pasteboard: pasteboard)

        let targetDocument = try documentRepository.create(Document(title: "Target"))
        let targetItem = try createItem(
            documentId: targetDocument.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Target block",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let targetViewModel = makeViewModel(document: targetDocument, store: store)
        targetViewModel.load()

        let pasted = try targetViewModel.pasteFromClipboard(
            at: DocumentTextLocation(blockId: targetItem.id, offset: 0), pasteboard: pasteboard
        )

        #expect(pasted.count == 1)
        #expect(pasted[0].documentId == targetDocument.id)
        // `offset: 0` inserts before the anchor block.
        #expect(targetViewModel.items.map(\.id) == [pasted[0].id, targetItem.id])

        // Persisted into the target document's own storage.
        #expect(try documentItemRepository.find(id: pasted[0].id)?.documentId == targetDocument.id)
        // The source document (and its original item) are untouched.
        #expect(try documentItemRepository.find(id: sourceItem.id)?.documentId == sourceDocument.id)
        #expect(pasted[0].id != sourceItem.id)
    }

    // MARK: - Common invariant 5 — every pasted block gets a fresh id

    @Test("Every pasted block receives a fresh id, never reusing the clipboard payload's original id")
    func pasteAlwaysAssignsFreshIds() throws {
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

        let payload = BlockClipboardPayload(
            items: [
                DocumentItem(id: "original-1", documentId: document.id, contentType: "text", orderKey: "01"),
                DocumentItem(id: "original-2", documentId: document.id, contentType: "text", orderKey: "02")
            ],
            textContents: [
                TextContent(itemId: "original-1", textKind: TextItemKind.paragraph, plainText: "one"),
                TextContent(itemId: "original-2", textKind: TextItemKind.paragraph, plainText: "two")
            ],
            listGroups: [],
            textMarks: []
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockPasteActionTests.freshIds")
        defer { UIPasteboard.remove(withName: .init("CrossBlockPasteActionTests.freshIds")) }
        try seedPasteboard(pasteboard, with: payload)

        let pasted = try viewModel.pasteFromClipboard(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.count == 2)
        #expect(pasted.map(\.id).allSatisfy { $0 != "original-1" && $0 != "original-2" })
        #expect(Set(pasted.map(\.id)).count == 2)
        #expect(viewModel.textContent(forItemId: pasted[0].id).plainText == "one")
        #expect(viewModel.textContent(forItemId: pasted[1].id).plainText == "two")
    }

    // MARK: - No app-format payload on the pasteboard

    @Test("Pasting a pasteboard with no com.semibold.blocks-payload entry no-ops instead of throwing")
    func pasteNoOpsWithoutAppFormatPayload() throws {
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

        let pasteboard = makeTestPasteboard(name: "CrossBlockPasteActionTests.plainTextOnly")
        defer { UIPasteboard.remove(withName: .init("CrossBlockPasteActionTests.plainTextOnly")) }
        pasteboard.string = "just some plain text copied elsewhere"

        let pasted = try viewModel.pasteFromClipboard(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.isEmpty)
        #expect(viewModel.items.map(\.id) == [anchor.id])
    }

    // MARK: - TextMark round-trip onto the new pasted item's id

    @Test("Pasting a block with a TextMark rewrites the mark onto the new pasted item's id, offsets/type unchanged")
    func pasteRewritesTextMarkOntoNewPastedItemId() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let textMarkRepository = TextMarkRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let anchor = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Anchor", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        // The clipboard payload's mark references the ORIGINAL item id
        // ("src-1") — the same shape `CrossBlockSelectionClipboardSerializer`
        // produces when copying a block that carries marks (see
        // `CrossBlockCutListReconciliationTests.copyClipsBoundaryBlockTextMarksToSelectedRange`).
        let payload = BlockClipboardPayload(
            items: [DocumentItem(id: "src-1", documentId: "other-doc", contentType: "text", orderKey: "01")],
            textContents: [TextContent(itemId: "src-1", textKind: TextItemKind.paragraph, plainText: "Hello world")],
            listGroups: [],
            textMarks: [TextMark(itemId: "src-1", startOffset: 0, endOffset: 5, markType: "bold")]
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockPasteActionTests.textMarkRewrite")
        defer { UIPasteboard.remove(withName: .init("CrossBlockPasteActionTests.textMarkRewrite")) }
        try seedPasteboard(pasteboard, with: payload)

        let pasted = try viewModel.pasteFromClipboard(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.count == 1)
        let newItemId = pasted[0].id
        #expect(newItemId != "src-1")

        // In-memory: `marksByItemId` (populated by `recordPastedMarks`)
        // points at the NEW pasted item's id, not the original.
        let inMemoryMarks = viewModel.marksByItemId[newItemId] ?? []
        #expect(inMemoryMarks.count == 1)
        let inMemoryMark = try #require(inMemoryMarks.first)
        #expect(inMemoryMark.itemId == newItemId)
        #expect(inMemoryMark.startOffset == 0)
        #expect(inMemoryMark.endOffset == 5)
        #expect(inMemoryMark.markType == "bold")
        #expect(viewModel.marksByItemId["src-1"] == nil)

        // Persisted, not just in-memory.
        let persistedMarks = try textMarkRepository.marks(itemId: newItemId)
        #expect(persistedMarks.count == 1)
        let persistedMark = try #require(persistedMarks.first)
        #expect(persistedMark.itemId == newItemId)
        #expect(persistedMark.startOffset == 0)
        #expect(persistedMark.endOffset == 5)
        #expect(persistedMark.markType == "bold")
    }
}
