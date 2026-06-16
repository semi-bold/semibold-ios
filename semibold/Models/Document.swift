import Foundation
import GRDB

/// A single document the user is writing.
///
/// A document lives inside a folder (or at the top level when
/// `folderId` is `nil`) and is made up of an ordered tree of
/// `DocumentBlock`s that hold its actual content.
struct Document: Identifiable, Equatable, Hashable, Codable {
    var id: String
    var folderId: String?
    var title: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        folderId: String? = nil,
        title: String = "Untitled",
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.title = title
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension Document: FetchableRecord, PersistableRecord {
    static let databaseTableName = "documents"
}
