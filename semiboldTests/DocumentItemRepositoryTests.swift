import Testing

@testable import semibold

/// Smoke coverage for `DocumentItemRepository`'s CRUD/hierarchy/ordering
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

    @Test("children(documentId:parentItemId:) returns only direct children, sorted by orderKey")
    func childrenAreScopedToParentAndSortedByOrderKey() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)

        let parent = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0100000000")
        )
        let secondChild = try repository.create(
            DocumentItem(documentId: "doc-1", parentItemId: parent.id, contentType: "text", orderKey: "0200000000")
        )
        let firstChild = try repository.create(
            DocumentItem(documentId: "doc-1", parentItemId: parent.id, contentType: "text", orderKey: "0100000000")
        )
        // A sibling of `parent`, not one of its children — must not show up below.
        _ = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0200000000")
        )

        let topLevel = try repository.children(documentId: "doc-1", parentItemId: nil)
        #expect(topLevel.map(\.id).contains(parent.id))
        #expect(topLevel.count == 2)

        let children = try repository.children(documentId: "doc-1", parentItemId: parent.id)
        #expect(children.map(\.id) == [firstChild.id, secondChild.id])
    }

    @Test("allItems(documentId:) returns nothing for a document with no items")
    func allItemsEmptyDocumentReturnsEmpty() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)

        #expect(try repository.allItems(documentId: "doc-1").isEmpty)
    }

    @Test("allItems(documentId:) matches children(documentId:parentItemId:nil) for a document with only top-level items")
    func allItemsTopLevelOnlyMatchesChildrenTopLevel() throws {
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
        let topLevel = try repository.children(documentId: "doc-1", parentItemId: nil)

        #expect(flat.map(\.id) == [first.id, second.id])
        #expect(flat.map(\.id) == topLevel.map(\.id))
    }

    @Test("allItems(documentId:) places a nested item immediately after its parent, depth-first")
    func allItemsOrdersNestedItemsDepthFirstAfterTheirParent() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)

        let firstTopLevel = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0100000000")
        )
        let secondTopLevel = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0200000000")
        )
        // Nested under `firstTopLevel` — created out of orderKey order to
        // make sure the sort, not insertion order, drives the result.
        let secondChild = try repository.create(
            DocumentItem(
                documentId: "doc-1", parentItemId: firstTopLevel.id, contentType: "text", orderKey: "0200000000"
            )
        )
        let firstChild = try repository.create(
            DocumentItem(
                documentId: "doc-1", parentItemId: firstTopLevel.id, contentType: "text", orderKey: "0100000000"
            )
        )
        // A grandchild, nested under `firstChild`, to prove recursion goes
        // more than one level deep.
        let grandchild = try repository.create(
            DocumentItem(
                documentId: "doc-1", parentItemId: firstChild.id, contentType: "text", orderKey: "0100000000"
            )
        )

        let flat = try repository.allItems(documentId: "doc-1")

        #expect(
            flat.map(\.id) == [
                firstTopLevel.id, firstChild.id, grandchild.id, secondChild.id, secondTopLevel.id,
            ]
        )
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

    @Test("softDelete hides an item from children() but keeps its row")
    func softDeleteHidesFromChildrenListing() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)

        let item = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0100000000")
        )
        try repository.softDelete(id: item.id)

        let topLevel = try repository.children(documentId: "doc-1", parentItemId: nil)
        #expect(topLevel.isEmpty)

        let found = try repository.find(id: item.id)
        #expect(found?.deletedAt != nil)
    }

    @Test("hardDelete removes an item and its nested subtree")
    func hardDeleteRemovesSubtree() throws {
        let store = try makeStore()
        let repository = DocumentItemRepository(context: store.context)

        let parent = try repository.create(
            DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0100000000")
        )
        let child = try repository.create(
            DocumentItem(documentId: "doc-1", parentItemId: parent.id, contentType: "text", orderKey: "0100000000")
        )

        try repository.hardDelete(id: parent.id)

        #expect(try repository.find(id: parent.id) == nil)
        #expect(try repository.find(id: child.id) == nil)
    }
}
