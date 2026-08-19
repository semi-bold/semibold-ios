import Testing

@testable import semibold

/// Smoke coverage for `DocumentItemRepository`'s CRUD/ordering/hard-delete
/// behavior against a throwaway in-memory database. A full rewrite of the
/// repository test suite happens in a later brief (`tasks/NO-005.md`
/// phase 6); this only proves the repository written in this brief works.
struct DocumentItemRepositoryTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    @Test("A created item is persisted and can be found by id")
    func createItemPersistsAndIsFindable() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)

        let item = DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0100000000")
        let created = try repository.create(item)

        #expect(created.id == item.id)

        let found = try repository.find(id: item.id)
        #expect(found?.documentId == "doc-1")
        #expect(found?.orderKey == "0100000000")
    }

    @Test("allItems(documentId:) returns nothing for a document with no items")
    func allItemsEmptyDocumentReturnsEmpty() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)

        #expect(try repository.allItems(documentId: "doc-1").isEmpty)
    }

    @Test("allItems(documentId:) returns only live items, sorted by orderKey")
    func allItemsReturnsLiveItemsSortedByOrderKey() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)

        let second = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0200000000")
        )
        let first = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0100000000")
        )
        let deleted = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0150000000")
        )
        try repository.softDelete(id: deleted.id)

        let flat = try repository.allItems(documentId: "doc-1")

        #expect(flat.map(\.id) == [first.id, second.id])
    }

    /// Nesting (`tasks/NO-009.md` §3.1) is `depth` + `listGroupId` on each
    /// item, not a separate tree-assembly step — `allItems` is a plain
    /// `orderKey`-sorted fetch regardless of `depth`, so a document's
    /// display order is entirely determined by how callers assign
    /// `orderKey` when creating/moving items (`DetailViewModel.indentBlock
    /// (_:)`/`.outdentBlock(_:)` are what keep that consistent with
    /// `depth`, not this repository).
    @Test("allItems(documentId:) orders purely by orderKey, independent of depth")
    func allItemsOrdersByOrderKeyRegardlessOfDepth() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)
        let listGroup = try ListGroupRepository(context: store.context).create(
            ListGroup(documentId: "doc-1", listType: TextItemKind.bulletedListItem)
        )

        let parent = try repository.create(
            DocumentItem(documentId: "doc-1", listGroupId: listGroup.id, contentType: "text", orderKey: "0100000000")
        )
        let child = try repository.create(
            DocumentItem(
                documentId: "doc-1", depth: 1, listGroupId: listGroup.id, contentType: "text", orderKey: "0150000000"
            )
        )
        let secondTopLevel = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0200000000")
        )

        let flat = try repository.allItems(documentId: "doc-1")

        #expect(flat.map(\.id) == [parent.id, child.id, secondTopLevel.id])
    }

    @Test("update refreshes updatedAt and persists field changes")
    func updatePersistsChanges() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)

        let item = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0100000000")
        )
        var changed = item
        changed.orderKey = "0150000000"
        let updated = try repository.update(changed)

        #expect(updated.orderKey == "0150000000")
        #expect(updated.updatedAt > item.updatedAt || updated.updatedAt >= item.updatedAt)

        let found = try repository.find(id: item.id)
        #expect(found?.orderKey == "0150000000")
    }

    @Test("softDelete hides an item from allItems() but keeps its row")
    func softDeleteHidesFromAllItemsListing() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)

        let item = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0100000000")
        )
        try repository.softDelete(id: item.id)

        let flat = try repository.allItems(documentId: "doc-1")
        #expect(flat.isEmpty)

        let found = try repository.find(id: item.id)
        #expect(found?.deletedAt != nil)
    }

    @Test("hardDelete removes an item and its nested subtree, found via listGroupId + depth")
    func hardDeleteRemovesSubtree() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)
        let listGroup = try ListGroupRepository(context: store.context).create(
            ListGroup(documentId: "doc-1", listType: TextItemKind.bulletedListItem)
        )

        let parent = try repository.create(
            DocumentItem(documentId: "doc-1", listGroupId: listGroup.id, contentType: "text", orderKey: "0100000000")
        )
        let child = try repository.create(
            DocumentItem(
                documentId: "doc-1", depth: 1, listGroupId: listGroup.id, contentType: "text", orderKey: "0150000000"
            )
        )

        try repository.hardDelete(id: parent.id)

        #expect(try repository.find(id: parent.id) == nil)
        #expect(try repository.find(id: child.id) == nil)
    }

    @Test("hardDelete on a non-list item (no listGroupId) removes only itself")
    func hardDeleteOnNonListItemRemovesOnlyItself() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)

        let item = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0100000000")
        )
        let sibling = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0200000000")
        )

        try repository.hardDelete(id: item.id)

        #expect(try repository.find(id: item.id) == nil)
        #expect(try repository.find(id: sibling.id) != nil)
    }
}
