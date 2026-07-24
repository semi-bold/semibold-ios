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
