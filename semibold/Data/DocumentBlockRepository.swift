import CoreData
import Foundation

/// Reads and writes `DocumentBlock` rows.
///
/// Deleting a block is a soft delete: the row stays in the database with
/// `deletedAt` set so it can be restored or permanently purged later, and
/// disappears from the document the editor normally renders.
struct DocumentBlockRepository {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = DatabaseManager.sharedOrFallbackContext) {
        self.context = context
    }

    /// Inserts a new block.
    @discardableResult
    func create(_ block: DocumentBlock) throws -> DocumentBlock {
        let entity = DocumentBlockEntity(context: context)
        apply(block, to: entity)
        try context.save()
        return block
    }

    /// Fetches a single block by id, including soft-deleted ones.
    func find(id: String) throws -> DocumentBlock? {
        try fetchEntity(id: id).map(DocumentBlock.init(entity:))
    }

    /// Fetches the blocks that live directly under `parentId` within
    /// `documentId` (or at the document's top level when `parentId` is
    /// `nil`), excluding soft-deleted blocks, in display order.
    func blocks(documentId: String, parentId: String?) throws -> [DocumentBlock] {
        let request = DocumentBlockEntity.fetchRequest()
        let documentPredicate = NSPredicate(format: "document.id == %@", documentId)
        let deletedPredicate = NSPredicate(format: "deletedAt == nil")
        let parentPredicate: NSPredicate
        if let parentId {
            parentPredicate = NSPredicate(format: "parent.id == %@", parentId)
        } else {
            parentPredicate = NSPredicate(format: "parent == nil")
        }
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [documentPredicate, deletedPredicate, parentPredicate]
        )
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return try context.fetch(request).map(DocumentBlock.init(entity:))
    }

    /// Fetches every block belonging to `documentId`, including nested
    /// ones, excluding soft-deleted blocks, in display order. Useful for
    /// loading a whole document at once and assembling its block tree in
    /// memory.
    func allBlocks(documentId: String) throws -> [DocumentBlock] {
        let request = DocumentBlockEntity.fetchRequest()
        let documentPredicate = NSPredicate(format: "document.id == %@", documentId)
        let deletedPredicate = NSPredicate(format: "deletedAt == nil")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [documentPredicate, deletedPredicate])
        request.sortDescriptors = [
            NSSortDescriptor(key: "parent.id", ascending: true),
            NSSortDescriptor(key: "sortOrder", ascending: true)
        ]
        return try context.fetch(request).map(DocumentBlock.init(entity:))
    }

    /// Saves changes to an existing block, refreshing `updatedAt`.
    @discardableResult
    func update(_ block: DocumentBlock) throws -> DocumentBlock {
        var updated = block
        updated.updatedAt = Date()
        guard let entity = try fetchEntity(id: updated.id) else {
            throw RepositoryError.recordNotFound
        }
        apply(updated, to: entity)
        try context.save()
        return updated
    }

    /// Marks a block as deleted without removing its row, so it can be
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

    /// Permanently removes a block row. Intended for purging
    /// already-soft-deleted blocks, not for everyday delete actions.
    ///
    /// Core Data's `Deny` delete rule on `DocumentBlock.children` blocks
    /// the save if nested blocks are still attached, since there's no
    /// automatic cascade. To keep this call behaving like the previous
    /// single-row GRDB delete, it recurses through the block's children
    /// first, deleting the whole subtree regardless of each child's own
    /// `deletedAt` state.
    func hardDelete(id: String) throws {
        guard let entity = try fetchEntity(id: id) else { return }
        deleteSubtree(of: entity)
        context.delete(entity)
        try context.save()
    }

    /// Recursively deletes every block nested under `entity`, so the
    /// block can be removed without the `Deny` rule rejecting the save.
    private func deleteSubtree(of entity: DocumentBlockEntity) {
        let children = (entity.children as? Set<DocumentBlockEntity>) ?? []
        for child in children {
            deleteSubtree(of: child)
            context.delete(child)
        }
    }

    private func fetchEntity(id: String) throws -> DocumentBlockEntity? {
        let request = DocumentBlockEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func apply(_ block: DocumentBlock, to entity: DocumentBlockEntity) {
        entity.id = block.id
        entity.sortOrder = Int64(block.sortOrder)
        entity.type = block.type.rawValue
        entity.contentJSON = block.contentJSON
        entity.markdownSource = block.markdownSource
        entity.createdAt = block.createdAt
        entity.updatedAt = block.updatedAt
        entity.deletedAt = block.deletedAt

        let documentRequest = DocumentEntity.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", block.documentId)
        documentRequest.fetchLimit = 1
        entity.document = try? context.fetch(documentRequest).first

        if let parentId = block.parentId {
            entity.parent = try? fetchEntity(id: parentId)
        } else {
            entity.parent = nil
        }
    }
}

private extension DocumentBlock {
    init(entity: DocumentBlockEntity) {
        self.init(
            id: entity.id ?? "",
            documentId: entity.document?.id ?? "",
            parentId: entity.parent?.id,
            sortOrder: Int(entity.sortOrder),
            type: BlockType(rawValue: entity.type ?? "") ?? .paragraph,
            contentJSON: entity.contentJSON ?? "",
            markdownSource: entity.markdownSource,
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date(),
            deletedAt: entity.deletedAt
        )
    }
}
