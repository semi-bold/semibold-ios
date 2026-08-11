import CoreData
import Foundation

/// Reads and writes `Folder` rows.
///
/// Deleting a folder is a soft delete: the row stays in the database
/// with `deletedAt` set so it can be restored or permanently purged
/// later, and disappears from the lists callers normally fetch.
struct FolderRepository {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = DatabaseManager.sharedOrFallbackContext) {
        self.context = context
    }

    /// Inserts a new folder.
    @discardableResult
    func create(_ folder: Folder) throws -> Folder {
        let entity = FolderEntity(context: context)
        apply(folder, to: entity)
        try context.save()
        return folder
    }

    /// Fetches a single folder by id, including soft-deleted ones.
    func find(id: String) throws -> Folder? {
        try fetchEntity(id: id).map(Folder.init(entity:))
    }

    /// Fetches the direct children of `parentId` (or the top-level
    /// folders when `parentId` is `nil`), excluding soft-deleted
    /// folders, newest-created first — personal document management reads
    /// best most-recent-first, with keyword search covering lookup of
    /// older items, rather than a manually-managed position (`sortOrder`
    /// exists on the entity but is never set to anything but its default
    /// and isn't used for ordering).
    func children(of parentId: String?) throws -> [Folder] {
        let request = FolderEntity.fetchRequest()
        let deletedPredicate = NSPredicate(format: "deletedAt == nil")
        let parentPredicate: NSPredicate
        if let parentId {
            parentPredicate = NSPredicate(format: "parent.id == %@", parentId)
        } else {
            parentPredicate = NSPredicate(format: "parent == nil")
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [deletedPredicate, parentPredicate])
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request).map(Folder.init(entity:))
    }

    /// Whether `parentId` has any live (non-soft-deleted) nested folders.
    /// Used to warn the person deleting a folder that it isn't empty —
    /// pair with `DocumentRepository.hasDocuments(in:)` to also check for
    /// nested documents.
    func hasChildren(of parentId: String) throws -> Bool {
        let request = FolderEntity.fetchRequest()
        let deletedPredicate = NSPredicate(format: "deletedAt == nil")
        let parentPredicate = NSPredicate(format: "parent.id == %@", parentId)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [deletedPredicate, parentPredicate])
        request.fetchLimit = 1
        return try context.count(for: request) > 0
    }

    /// Returns the number of live (non-soft-deleted) direct child folders
    /// of `parentId`. Used alongside `DocumentRepository.count(in:)` to
    /// display the total item count on each folder row.
    func childCount(of parentId: String) throws -> Int {
        let request = FolderEntity.fetchRequest()
        let deletedPredicate = NSPredicate(format: "deletedAt == nil")
        let parentPredicate = NSPredicate(format: "parent.id == %@", parentId)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [deletedPredicate, parentPredicate])
        return try context.count(for: request)
    }

    /// Searches every non-deleted folder across the entire tree (not just
    /// one parent's direct children) for a name match.
    ///
    /// A blank keyword returns no results rather than the whole tree —
    /// the search drawer shows nothing until the person starts typing.
    func search(keyword: String) throws -> [Folder] {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else { return [] }

        let request = FolderEntity.fetchRequest()
        let deletedPredicate = NSPredicate(format: "deletedAt == nil")
        let namePredicate = NSPredicate(format: "name CONTAINS[cd] %@", trimmedKeyword)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [deletedPredicate, namePredicate])
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request).map(Folder.init(entity:))
    }

    /// Saves changes to an existing folder, refreshing `updatedAt`.
    @discardableResult
    func update(_ folder: Folder) throws -> Folder {
        var updated = folder
        updated.updatedAt = Date()
        guard let entity = try fetchEntity(id: updated.id) else {
            throw RepositoryError.recordNotFound
        }
        apply(updated, to: entity)
        try context.save()
        return updated
    }

    /// Marks a folder as deleted without removing its row, so it can be
    /// restored later.
    func softDelete(id: String) throws {
        guard let entity = try fetchEntity(id: id) else {
            throw RepositoryError.recordNotFound
        }
        let now = Date()
        entity.deletedAt = now
        entity.updatedAt = now
        try context.save()
    }

    /// Permanently removes a folder row and its entire subtree. Intended
    /// for purging already-soft-deleted folders, not for everyday delete
    /// actions.
    ///
    /// ⚠️ This cascades through every nested child folder/document/block
    /// **regardless of each descendant's own `deletedAt` state** — it
    /// will just as happily purge live (non-soft-deleted) data as
    /// soft-deleted data. Core Data's `Deny` delete rule on
    /// `Folder.children`/`Folder.documents` blocks the save if any child
    /// row is still attached (no automatic cascade), so this recurses
    /// through child folders/documents (and their blocks) first to clear
    /// that constraint. Callers wiring up a "delete folder" UI must
    /// soft-delete (or confirm with the user) before calling this —
    /// there is no built-in guard against permanently deleting active
    /// user data.
    func hardDelete(id: String) throws {
        guard let entity = try fetchEntity(id: id) else { return }
        try deleteSubtree(of: entity)
        context.delete(entity)
        try context.save()
    }

    /// Recursively detaches and deletes every folder/document (and its
    /// blocks) nested under `entity`, so the parent can be removed
    /// without the `Deny` rule rejecting the save.
    private func deleteSubtree(of entity: FolderEntity) throws {
        let childFolders = (entity.children as? Set<FolderEntity>) ?? []
        for child in childFolders {
            try deleteSubtree(of: child)
            context.delete(child)
        }

        let childDocuments = (entity.documents as? Set<DocumentEntity>) ?? []
        let documentRepository = DocumentRepository(context: context)
        for document in childDocuments {
            try documentRepository.deleteSubtree(of: document)
            context.delete(document)
        }
    }

    /// Permanently removes every root-level folder (`parent == nil`) —
    /// including ones already soft-deleted, not just live ones. Each root
    /// folder's own `hardDelete(id:)` already cascades through its entire
    /// subtree, so calling this for every root folder clears every
    /// `Folder`/`Document`/`DocumentItem`/`TextItem`/`TextMark`/`MediaItem`
    /// row in the store. Used by account deletion's full local wipe
    /// (`tasks/NO-008.md` §5.2) — not for everyday delete-folder UI, which
    /// soft-deletes instead.
    func hardDeleteAll() throws {
        let request = FolderEntity.fetchRequest()
        request.predicate = NSPredicate(format: "parent == nil")
        for entity in try context.fetch(request) {
            guard let id = entity.id else { continue }
            try hardDelete(id: id)
        }
    }

    private func fetchEntity(id: String) throws -> FolderEntity? {
        let request = FolderEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func apply(_ folder: Folder, to entity: FolderEntity) {
        entity.id = folder.id
        entity.name = folder.name
        entity.sortOrder = Int64(folder.sortOrder)
        entity.createdAt = folder.createdAt
        entity.updatedAt = folder.updatedAt
        entity.deletedAt = folder.deletedAt
        if let parentId = folder.parentId {
            entity.parent = try? fetchEntity(id: parentId)
        } else {
            entity.parent = nil
        }
    }
}

private extension Folder {
    init(entity: FolderEntity) {
        self.init(
            id: entity.id ?? "",
            parentId: entity.parent?.id,
            name: entity.name ?? "",
            sortOrder: Int(entity.sortOrder),
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date(),
            deletedAt: entity.deletedAt
        )
    }
}
