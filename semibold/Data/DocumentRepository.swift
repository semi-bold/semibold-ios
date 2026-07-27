import CoreData
import Foundation

/// Reads and writes `Document` rows.
///
/// Deleting a document is a soft delete: the row stays in the database
/// with `deletedAt` set so it can be restored or permanently purged
/// later, and disappears from the lists callers normally fetch.
struct DocumentRepository {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = DatabaseManager.sharedOrFallbackContext) {
        self.context = context
    }

    /// Inserts a new document.
    @discardableResult
    func create(_ document: Document) throws -> Document {
        let entity = DocumentEntity(context: context)
        apply(document, to: entity)
        try context.save()
        return document
    }

    /// Fetches a single document by id, including soft-deleted ones.
    func find(id: String) throws -> Document? {
        try fetchEntity(id: id).map(Document.init(entity:))
    }

    /// Fetches the documents that live directly inside `folderId` (or at
    /// the top level when `folderId` is `nil`), excluding soft-deleted
    /// documents, newest-created first — personal document management
    /// reads best most-recent-first, with keyword search covering lookup
    /// of older items, rather than a manually-managed position
    /// (`sortOrder` exists on the entity but is never set to anything but
    /// its default and isn't used for ordering).
    func documents(in folderId: String?) throws -> [Document] {
        let request = DocumentEntity.fetchRequest()
        let deletedPredicate = NSPredicate(format: "deletedAt == nil")
        let folderPredicate: NSPredicate
        if let folderId {
            folderPredicate = NSPredicate(format: "folder.id == %@", folderId)
        } else {
            folderPredicate = NSPredicate(format: "folder == nil")
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [deletedPredicate, folderPredicate])
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request).map(Document.init(entity:))
    }

    /// Whether `folderId` directly contains any live (non-soft-deleted)
    /// documents. Used alongside `FolderRepository.hasChildren(of:)` to
    /// warn the person deleting a folder that it isn't empty.
    func hasDocuments(in folderId: String) throws -> Bool {
        let request = DocumentEntity.fetchRequest()
        let deletedPredicate = NSPredicate(format: "deletedAt == nil")
        let folderPredicate = NSPredicate(format: "folder.id == %@", folderId)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [deletedPredicate, folderPredicate])
        request.fetchLimit = 1
        return try context.count(for: request) > 0
    }

    /// Returns the number of live (non-soft-deleted) documents directly
    /// inside `folderId`. Used alongside `FolderRepository.childCount(of:)`
    /// to display the total item count on each folder row.
    func count(in folderId: String) throws -> Int {
        let request = DocumentEntity.fetchRequest()
        let deletedPredicate = NSPredicate(format: "deletedAt == nil")
        let folderPredicate = NSPredicate(format: "folder.id == %@", folderId)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [deletedPredicate, folderPredicate])
        return try context.count(for: request)
    }

    /// Saves changes to an existing document, refreshing `updatedAt`.
    @discardableResult
    func update(_ document: Document) throws -> Document {
        var updated = document
        updated.updatedAt = Date()
        guard let entity = try fetchEntity(id: updated.id) else {
            throw RepositoryError.recordNotFound
        }
        apply(updated, to: entity)
        try context.save()
        return updated
    }

    /// Marks a document as deleted without removing its row, so it can
    /// be restored later.
    func softDelete(id: String) throws {
        guard let entity = try fetchEntity(id: id) else {
            throw RepositoryError.recordNotFound
        }
        let now = Date()
        entity.deletedAt = now
        entity.updatedAt = now
        try context.save()
    }

    /// Permanently removes a document row and all its content items.
    /// Intended for purging already-soft-deleted documents, not for
    /// everyday delete actions.
    ///
    /// ⚠️ This cascades through every content item in the document
    /// **regardless of each item's own `deletedAt` state** — it will
    /// just as happily purge live (non-soft-deleted) content as
    /// soft-deleted content. Callers wiring up a "delete document" UI
    /// must soft-delete (or confirm with the user) before calling this —
    /// there is no built-in guard against permanently deleting active
    /// content.
    func hardDelete(id: String) throws {
        guard let entity = try fetchEntity(id: id) else { return }
        try deleteSubtree(of: entity)
        context.delete(entity)
        try context.save()
    }

    /// Permanently removes every content item belonging to `entity`, so
    /// the document can be removed without leaving orphaned item rows
    /// behind. `DocumentItem` has no Core Data relationship back to
    /// `Document` — like `DocumentItemRepository` itself, this queries
    /// the document's top-level items by `documentId` and hands each one
    /// to `DocumentItemRepository.hardDelete`, which already recurses
    /// through the rest of that item's own subtree plus its associated
    /// text/media detail rows. Shared with `FolderRepository.hardDelete`,
    /// which deletes nested documents the same way before removing their
    /// containing folder.
    func deleteSubtree(of entity: DocumentEntity) throws {
        guard let documentId = entity.id else { return }
        let request = DocumentItemEntity.fetchRequest()
        let documentPredicate = NSPredicate(format: "documentId == %@", documentId)
        let topLevelPredicate = NSPredicate(format: "parentItemId == nil")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [documentPredicate, topLevelPredicate])
        let itemRepository = DocumentItemRepository(context: context)
        for item in try context.fetch(request) {
            guard let itemId = item.id else { continue }
            try itemRepository.hardDelete(id: itemId)
        }
    }

    private func fetchEntity(id: String) throws -> DocumentEntity? {
        let request = DocumentEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func apply(_ document: Document, to entity: DocumentEntity) {
        entity.id = document.id
        entity.title = document.title
        entity.sortOrder = Int64(document.sortOrder)
        entity.createdAt = document.createdAt
        entity.updatedAt = document.updatedAt
        entity.deletedAt = document.deletedAt
        if let folderId = document.folderId {
            let folderRequest = FolderEntity.fetchRequest()
            folderRequest.predicate = NSPredicate(format: "id == %@", folderId)
            folderRequest.fetchLimit = 1
            entity.folder = try? context.fetch(folderRequest).first
        } else {
            entity.folder = nil
        }
    }
}

private extension Document {
    init(entity: DocumentEntity) {
        self.init(
            id: entity.id ?? "",
            folderId: entity.folder?.id,
            title: entity.title ?? "Untitled",
            sortOrder: Int(entity.sortOrder),
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date(),
            deletedAt: entity.deletedAt
        )
    }
}
