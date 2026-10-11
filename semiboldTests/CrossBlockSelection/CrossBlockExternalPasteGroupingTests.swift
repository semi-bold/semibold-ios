import Foundation
import Testing
import UIKit

@testable import semibold

/// Split out of `CrossBlockExternalTextPasteTests` (same `file_length`
/// -headroom precedent as `CrossBlockPasteListReconciliationTests`) —
/// covers AC5 of the `05-external-text-paste` brief: consecutive
/// list-prefixed lines in the SAME pasted text share one freshly created
/// `ListGroup` (`ListBlock/README.md` A2(b-e)'s "join an adjacent
/// same-kind list" bookkeeping, scoped to just the newly pasted lines —
/// see `ExternalTextPasteParser`'s own doc comment), and a non-list line
/// (or a different list kind) breaks the run instead of merging two runs
/// into one group.
@MainActor
struct CrossBlockExternalPasteGroupingTests {
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
        textKind: String,
        plainText: String,
        documentItemRepository: DocumentItemRepository,
        textItemRepository: TextItemRepository
    ) throws -> DocumentItem {
        let item = try documentItemRepository.create(
            DocumentItem(documentId: documentId, contentType: "text", orderKey: orderKey)
        )
        _ = try textItemRepository.create(TextContent(itemId: item.id, textKind: textKind, plainText: plainText))
        return item
    }

    @Test("Three or more consecutive bulleted-list-prefix lines share exactly one new ListGroup")
    func consecutiveListPrefixLinesShareOneNewGroup() throws {
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

        let pasteboard = makeTestPasteboard(name: "CrossBlockExternalPasteGroupingTests.threeInARow")
        defer { UIPasteboard.remove(withName: .init("CrossBlockExternalPasteGroupingTests.threeInARow")) }
        pasteboard.string = "- one\n- two\n- three"

        let pasted = try viewModel.pasteExternalText(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.count == 3)
        let groupIds = Set(pasted.compactMap(\.listGroupId))
        #expect(groupIds.count == 1)
        #expect(pasted.allSatisfy { $0.listGroupId != nil })

        // The group is a real, persisted row of the right kind.
        let groupId = try #require(groupIds.first)
        let group = try #require(try listGroupRepository.find(id: groupId))
        #expect(group.listType == TextItemKind.bulletedListItem)
        #expect(group.documentId == document.id)

        for item in pasted {
            #expect(try documentItemRepository.find(id: item.id)?.listGroupId == groupId)
        }
    }

    @Test("A non-list line between two list-prefix runs keeps them in two separate ListGroups")
    func nonListLineBreaksGroupingIntoTwoSeparateGroups() throws {
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

        let pasteboard = makeTestPasteboard(name: "CrossBlockExternalPasteGroupingTests.brokenRun")
        defer { UIPasteboard.remove(withName: .init("CrossBlockExternalPasteGroupingTests.brokenRun")) }
        pasteboard.string = "- first run item\nA plain separator\n- second run item"

        let pasted = try viewModel.pasteExternalText(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.count == 3)
        let firstGroupId = pasted[0].listGroupId
        let secondGroupId = pasted[2].listGroupId

        #expect(pasted[1].listGroupId == nil)
        #expect(firstGroupId != nil)
        #expect(secondGroupId != nil)
        // The two runs never merge into one group, even though they're
        // the same list kind — the plain line in between breaks the run.
        #expect(firstGroupId != secondGroupId)
    }

    @Test("A different list kind between two same-kind lines does not merge them into one group")
    func differentListKindDoesNotMergeIntoOneGroup() throws {
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

        let pasteboard = makeTestPasteboard(name: "CrossBlockExternalPasteGroupingTests.differentKind")
        defer { UIPasteboard.remove(withName: .init("CrossBlockExternalPasteGroupingTests.differentKind")) }
        // Bulleted, then numbered (different kind), then bulleted again.
        pasteboard.string = "- bullet one\n1. numbered one\n- bullet two"

        let pasted = try viewModel.pasteExternalText(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.count == 3)
        let bulletGroupIds = [pasted[0].listGroupId, pasted[2].listGroupId]
        #expect(bulletGroupIds[0] != nil)
        #expect(bulletGroupIds[0] != bulletGroupIds[1])
        #expect(pasted[1].listGroupId != pasted[0].listGroupId)
    }
}
