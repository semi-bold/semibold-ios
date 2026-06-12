import Foundation
import GRDB

/// Reads and writes `DocumentBlock` rows.
///
/// Deleting a block is a soft delete: the row stays in the database with
/// `deletedAt` set so it can be restored or permanently purged later, and
/// disappears from the document the editor normally renders.
struct DocumentBlockRepository {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    /// Inserts a new block.
    @discardableResult
    func create(_ block: DocumentBlock) throws -> DocumentBlock {
        try dbQueue.write { db in
            try block.inserted(db)
        }
    }

    /// Fetches a single block by id, including soft-deleted ones.
    func find(id: String) throws -> DocumentBlock? {
        try dbQueue.read { db in
            try DocumentBlock.fetchOne(db, key: id)
        }
    }

    /// Fetches the blocks that live directly under `parentId` within
    /// `documentId` (or at the document's top level when `parentId` is
    /// `nil`), excluding soft-deleted blocks, in display order.
    func blocks(documentId: String, parentId: String?) throws -> [DocumentBlock] {
        try dbQueue.read { db in
            var query = DocumentBlock
                .filter(Column("documentId") == documentId)
                .filter(Column("deletedAt") == nil)
            if let parentId {
                query = query.filter(Column("parentId") == parentId)
            } else {
                query = query.filter(Column("parentId") == nil)
            }
            return try query
                .order(Column("sortOrder"))
                .fetchAll(db)
        }
    }

    /// Fetches every block belonging to `documentId`, including nested
    /// ones, excluding soft-deleted blocks, in display order. Useful for
    /// loading a whole document at once and assembling its block tree in
    /// memory.
    func allBlocks(documentId: String) throws -> [DocumentBlock] {
        try dbQueue.read { db in
            try DocumentBlock
                .filter(Column("documentId") == documentId)
                .filter(Column("deletedAt") == nil)
                .order(Column("parentId"), Column("sortOrder"))
                .fetchAll(db)
        }
    }

    /// Saves changes to an existing block, refreshing `updatedAt`.
    @discardableResult
    func update(_ block: DocumentBlock) throws -> DocumentBlock {
        var updated = block
        updated.updatedAt = Date()
        return try dbQueue.write { db in
            try updated.update(db)
            return updated
        }
    }

    /// Marks a block as deleted without removing its row, so it can be
    /// restored later.
    func softDelete(id: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE document_blocks
                SET deletedAt = :deletedAt, updatedAt = :updatedAt
                WHERE id = :id
                """,
                arguments: ["id": id, "deletedAt": Date(), "updatedAt": Date()]
            )
        }
    }

    /// Permanently removes a block row. Intended for purging
    /// already-soft-deleted blocks, not for everyday delete actions.
    func hardDelete(id: String) throws {
        try dbQueue.write { db in
            _ = try DocumentBlock.deleteOne(db, key: id)
        }
    }
}
