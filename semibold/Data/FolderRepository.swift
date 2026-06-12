import Foundation
import GRDB

/// Reads and writes `Folder` rows.
///
/// Deleting a folder is a soft delete: the row stays in the database
/// with `deletedAt` set so it can be restored or permanently purged
/// later, and disappears from the lists callers normally fetch.
struct FolderRepository {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    /// Inserts a new folder.
    @discardableResult
    func create(_ folder: Folder) throws -> Folder {
        try dbQueue.write { db in
            try folder.inserted(db)
        }
    }

    /// Fetches a single folder by id, including soft-deleted ones.
    func find(id: String) throws -> Folder? {
        try dbQueue.read { db in
            try Folder.fetchOne(db, key: id)
        }
    }

    /// Fetches the direct children of `parentId` (or the top-level
    /// folders when `parentId` is `nil`), excluding soft-deleted
    /// folders, ordered for display.
    func children(of parentId: String?) throws -> [Folder] {
        try dbQueue.read { db in
            var query = Folder.filter(Column("deletedAt") == nil)
            if let parentId {
                query = query.filter(Column("parentId") == parentId)
            } else {
                query = query.filter(Column("parentId") == nil)
            }
            return try query
                .order(Column("sortOrder"), Column("createdAt"))
                .fetchAll(db)
        }
    }

    /// Saves changes to an existing folder, refreshing `updatedAt`.
    @discardableResult
    func update(_ folder: Folder) throws -> Folder {
        var updated = folder
        updated.updatedAt = Date()
        return try dbQueue.write { db in
            try updated.update(db)
            return updated
        }
    }

    /// Marks a folder as deleted without removing its row, so it can be
    /// restored later.
    func softDelete(id: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE folders
                SET deletedAt = :deletedAt, updatedAt = :updatedAt
                WHERE id = :id
                """,
                arguments: ["id": id, "deletedAt": Date(), "updatedAt": Date()]
            )
        }
    }

    /// Permanently removes a folder row. Intended for purging
    /// already-soft-deleted folders, not for everyday delete actions.
    func hardDelete(id: String) throws {
        try dbQueue.write { db in
            _ = try Folder.deleteOne(db, key: id)
        }
    }
}
