import Foundation
import GRDB

/// A folder in the user's local document tree.
///
/// Folders can be nested inside one another (`parentId` points at the
/// parent folder, or is `nil` for a top-level folder) and hold both
/// documents and other folders, ordered by `sortOrder`.
struct Folder: Identifiable, Equatable, Codable {
    var id: String
    var parentId: String?
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        parentId: String? = nil,
        name: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension Folder: FetchableRecord, PersistableRecord {
    static let databaseTableName = "folders"
}
