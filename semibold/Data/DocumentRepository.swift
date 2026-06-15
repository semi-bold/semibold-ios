import Foundation
import GRDB

/// Reads and writes `Document` rows.
///
/// Deleting a document is a soft delete: the row stays in the database
/// with `deletedAt` set so it can be restored or permanently purged
/// later, and disappears from the lists callers normally fetch.
struct DocumentRepository {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.sharedOrFallbackQueue) {
        self.dbQueue = dbQueue
    }

    /// Inserts a new document.
    @discardableResult
    func create(_ document: Document) throws -> Document {
        try dbQueue.write { db in
            try document.inserted(db)
        }
    }

    /// Fetches a single document by id, including soft-deleted ones.
    func find(id: String) throws -> Document? {
        try dbQueue.read { db in
            try Document.fetchOne(db, key: id)
        }
    }

    /// Fetches the documents that live directly inside `folderId` (or at
    /// the top level when `folderId` is `nil`), excluding soft-deleted
    /// documents, ordered for display.
    func documents(in folderId: String?) throws -> [Document] {
        try dbQueue.read { db in
            var query = Document.filter(Column("deletedAt") == nil)
            if let folderId {
                query = query.filter(Column("folderId") == folderId)
            } else {
                query = query.filter(Column("folderId") == nil)
            }
            return try query
                .order(Column("sortOrder"), Column("createdAt"))
                .fetchAll(db)
        }
    }

    /// Saves changes to an existing document, refreshing `updatedAt`.
    @discardableResult
    func update(_ document: Document) throws -> Document {
        var updated = document
        updated.updatedAt = Date()
        return try dbQueue.write { db in
            try updated.update(db)
            return updated
        }
    }

    /// Marks a document as deleted without removing its row, so it can
    /// be restored later.
    func softDelete(id: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE documents
                SET deletedAt = :deletedAt, updatedAt = :updatedAt
                WHERE id = :id
                """,
                arguments: ["id": id, "deletedAt": Date(), "updatedAt": Date()]
            )
        }
    }

    /// Permanently removes a document row. Intended for purging
    /// already-soft-deleted documents, not for everyday delete actions.
    func hardDelete(id: String) throws {
        try dbQueue.write { db in
            _ = try Document.deleteOne(db, key: id)
        }
    }
}
