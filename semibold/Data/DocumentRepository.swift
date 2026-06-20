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
    /// documents, ordered for display.
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
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
        return try context.fetch(request).map(Document.init(entity:))
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

    /// Permanently removes a document row and all its blocks. Intended
    /// for purging already-soft-deleted documents, not for everyday
    /// delete actions.
    ///
    /// ⚠️ This cascades through every block in the document **regardless
    /// of each block's own `deletedAt` state** — it will just as happily
    /// purge live (non-soft-deleted) content as soft-deleted content.
    /// Core Data's `Deny` delete rule on `Document.blocks` blocks the
    /// save if block rows are still attached (no automatic cascade), so
    /// this deletes the document's whole block set first to clear that
    /// constraint. Callers wiring up a "delete document" UI must
    /// soft-delete (or confirm with the user) before calling this — there
    /// is no built-in guard against permanently deleting active content.
    func hardDelete(id: String) throws {
        guard let entity = try fetchEntity(id: id) else { return }
        try deleteSubtree(of: entity)
        context.delete(entity)
        try context.save()
    }

    /// Detaches and deletes every block belonging to `entity`, so the
    /// document can be removed without the `Deny` rule on
    /// `Document.blocks` rejecting the save. `entity.blocks` is the
    /// document's *flat* set of every block regardless of nesting depth
    /// (the inverse of `DocumentBlock.document`, not just top-level
    /// blocks) — deleting it directly is correct and doesn't need to
    /// walk each block's own `parent`/`children` relationship. Shared
    /// with `FolderRepository.hardDelete`, which deletes nested documents
    /// the same way before removing their containing folder.
    func deleteSubtree(of entity: DocumentEntity) throws {
        let blocks = (entity.blocks as? Set<DocumentBlockEntity>) ?? []
        for block in blocks {
            context.delete(block)
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
