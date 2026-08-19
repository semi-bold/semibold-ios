import CoreData
import Foundation

/// Reads and writes `DocumentItem` rows — the structural nodes (position +
/// place in the hierarchy) of a document's content tree. The actual
/// content for each item lives in a type-specific detail table keyed by
/// the item's `id` (`TextItemRepository`, `MediaItemRepository`, …,
/// `tasks/NO-005.md` §4.3) — this repository only owns the shared
/// location/hierarchy/order fields every content element has in common.
///
/// Deleting an item is a soft delete: the row stays in the database with
/// `deletedAt` set so it can be restored or permanently purged later, and
/// disappears from the content lists callers normally fetch.
///
/// `DocumentItem` has no Core Data relationships — `documentId` and
/// `listGroupId` are plain string foreign keys, not relationship
/// traversals (`STORAGE_ARCHITECTURE.md` §5) — so every query here
/// predicates on those columns directly instead of walking
/// `entity.parent`/`entity.children` the way `FolderRepository` does.
struct DocumentItemRepository {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = DatabaseManager.sharedOrFallbackContext) {
        self.context = context
    }

    /// Inserts a new content item. Pass `save: false` to fold this into a
    /// caller's `context.withTransaction { ... }` alongside other
    /// repository mutations instead of committing on its own.
    @discardableResult
    func create(_ item: DocumentItem, save: Bool = true) throws -> DocumentItem {
        let entity = DocumentItemEntity(context: context)
        apply(item, to: entity)
        if save { try context.save() }
        return item
    }

    /// Fetches a single item by id, including soft-deleted ones.
    func find(id: String) throws -> DocumentItem? {
        try fetchEntity(id: id).map(DocumentItem.init(entity:))
    }

    /// Fetches **every** live (non-soft-deleted) item in `documentId`,
    /// ordered by `orderKey` — the string-based fractional index items
    /// are positioned by (`tasks/NO-005.md` §2.2), so plain
    /// lexicographic ascending order already matches display order.
    /// Nesting no longer requires a separate tree-assembly step: a list
    /// item's place in the hierarchy is its own stored `depth`, not a
    /// parent reference to walk (`tasks/NO-009.md` §3.1) — `orderKey`
    /// order alone is display order for every item, nested or not.
    func allItems(documentId: String) throws -> [DocumentItem] {
        let request = DocumentItemEntity.fetchRequest()
        let documentPredicate = NSPredicate(format: "documentId == %@", documentId)
        let deletedPredicate = NSPredicate(format: "deletedAt == nil")
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [documentPredicate, deletedPredicate]
        )
        request.sortDescriptors = [NSSortDescriptor(key: "orderKey", ascending: true)]
        return try context.fetch(request).map(DocumentItem.init(entity:))
    }

    /// Saves changes to an existing item, refreshing `updatedAt`. Pass
    /// `save: false` to fold this into a caller's `context.withTransaction
    /// { ... }` alongside other repository mutations instead of
    /// committing on its own.
    @discardableResult
    func update(_ item: DocumentItem, save: Bool = true) throws -> DocumentItem {
        var updated = item
        updated.updatedAt = Date()
        guard let entity = try fetchEntity(id: updated.id) else {
            throw RepositoryError.recordNotFound
        }
        apply(updated, to: entity)
        if save { try context.save() }
        return updated
    }

    /// Marks an item as deleted without removing its row, so it can be
    /// restored later. Pass `save: false` to fold this into a caller's
    /// `context.withTransaction { ... }` alongside other repository
    /// mutations instead of committing on its own.
    func softDelete(id: String, save: Bool = true) throws {
        guard let entity = try fetchEntity(id: id) else {
            throw RepositoryError.recordNotFound
        }
        let now = Date()
        entity.deletedAt = now
        entity.updatedAt = now
        if save { try context.save() }
    }

    /// Permanently removes an item row, its entire nested subtree, and
    /// their associated content detail rows. Intended for purging
    /// already-soft-deleted items, not for everyday delete actions.
    ///
    /// ⚠️ This cascades through every nested child item **regardless of
    /// each descendant's own `deletedAt` state** — it will just as
    /// happily purge live (non-soft-deleted) content as soft-deleted
    /// content. Because `DocumentItem` has no Core Data relationship to
    /// recurse through (unlike `FolderRepository`'s `Deny`-rule-driven
    /// subtree walk), this instead re-derives `id`'s descendants (found
    /// via its `listGroupId`, if it has one) to find and remove nested
    /// items before removing the item itself. Callers wiring up a
    /// "delete" UI must soft-delete (or confirm with the user) before
    /// calling this — there is no built-in guard against permanently
    /// deleting active content.
    func hardDelete(id: String) throws {
        guard let entity = try fetchEntity(id: id) else { return }
        try deleteSubtree(of: DocumentItem(entity: entity))
        try deleteAssociatedContent(itemId: id)
        context.delete(entity)
        try context.save()
    }

    /// Removes every item nested under `item` along with each one's own
    /// associated content rows. `item`'s descendants are whatever
    /// immediately follows it, in `orderKey` order, within the same
    /// `listGroupId`, up until the first item whose `depth` isn't
    /// greater than `item`'s own — the same contiguous-range reasoning
    /// as `DetailViewModel.subtreeRange(startingAt:)`, just expressed as
    /// a fetch instead of an in-memory array walk. Does nothing if
    /// `item` has no `listGroupId` (not a list item, so it can't have
    /// nested descendants at all).
    private func deleteSubtree(of item: DocumentItem) throws {
        guard let listGroupId = item.listGroupId else { return }
        let request = DocumentItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "listGroupId == %@", listGroupId)
        request.sortDescriptors = [NSSortDescriptor(key: "orderKey", ascending: true)]
        let groupMembers = try context.fetch(request)
        guard let rootIndex = groupMembers.firstIndex(where: { $0.id == item.id }) else { return }

        var end = rootIndex + 1
        while end < groupMembers.count, groupMembers[end].depth > item.depth {
            end += 1
        }
        for descendant in groupMembers[(rootIndex + 1)..<end] {
            guard let descendantId = descendant.id else { continue }
            try deleteAssociatedContent(itemId: descendantId)
            context.delete(descendant)
        }
    }

    /// Removes the type-specific detail rows (`TextItem`/`TextMark`/
    /// `MediaItem`) that belong to `itemId`, so a hard delete doesn't
    /// leave orphaned content rows behind.
    ///
    /// TODO(NO-005 §4.3): once `TextItemRepository`/`TextMarkRepository`/
    /// `MediaItemRepository` exist (this brief's next items), route this
    /// through them instead of fetching their entities directly — kept
    /// as a direct Core Data fetch here only because those repositories
    /// don't exist yet and this repository must not depend on them
    /// circularly. Does *not* cascade into the `Asset` row a `MediaItem`
    /// references (`assetId`): assets can be shared across multiple
    /// media items, so pruning orphaned assets is `AssetRepository`'s
    /// job, not this one's.
    private func deleteAssociatedContent(itemId: String) throws {
        let textItemRequest = TextItemEntity.fetchRequest()
        textItemRequest.predicate = NSPredicate(format: "itemId == %@", itemId)
        for entity in try context.fetch(textItemRequest) {
            context.delete(entity)
        }

        let textMarkRequest = TextMarkEntity.fetchRequest()
        textMarkRequest.predicate = NSPredicate(format: "itemId == %@", itemId)
        for entity in try context.fetch(textMarkRequest) {
            context.delete(entity)
        }

        let mediaItemRequest = MediaItemEntity.fetchRequest()
        mediaItemRequest.predicate = NSPredicate(format: "itemId == %@", itemId)
        for entity in try context.fetch(mediaItemRequest) {
            context.delete(entity)
        }
    }

    private func fetchEntity(id: String) throws -> DocumentItemEntity? {
        let request = DocumentItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func apply(_ item: DocumentItem, to entity: DocumentItemEntity) {
        entity.id = item.id
        entity.documentId = item.documentId
        entity.depth = Int64(item.depth)
        entity.listGroupId = item.listGroupId
        entity.contentType = item.contentType
        entity.orderKey = item.orderKey
        entity.revision = Int64(item.revision)
        entity.createdAt = item.createdAt
        entity.updatedAt = item.updatedAt
        entity.deletedAt = item.deletedAt
    }
}

private extension DocumentItem {
    init(entity: DocumentItemEntity) {
        self.init(
            id: entity.id ?? "",
            documentId: entity.documentId ?? "",
            depth: Int(entity.depth),
            listGroupId: entity.listGroupId,
            contentType: entity.contentType ?? "text",
            orderKey: entity.orderKey ?? "",
            revision: Int(entity.revision),
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date(),
            deletedAt: entity.deletedAt
        )
    }
}
