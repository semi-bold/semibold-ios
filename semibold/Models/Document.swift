import Foundation

/// A single document the user is writing.
///
/// A document lives inside a folder (or at the top level when
/// `folderId` is `nil`) and is made up of an ordered tree of
/// `DocumentItem`s that hold its actual content
/// (`tasks/NO-005.md` §3 "새 데이터 모델 개요").
struct Document: Identifiable, Hashable, Codable {
    var id: String
    var folderId: String?
    var title: String
    /// The document/content model version this document was written
    /// against, so a future model change can tell old documents apart
    /// from new ones and migrate them (`DOCUMENT_MODEL.md` §2.4).
    var schemaVersion: Int
    /// A per-save change counter. NO-005 only stores and increments this
    /// locally — comparing it across devices for conflict detection is
    /// out of scope until sync lands (`tasks/NO-005.md` §2.4, §6).
    var revision: Int
    /// This document's position among its siblings in the document
    /// list, lower first. Kept alongside the rewritten field set so
    /// existing per-user ordering keeps working unchanged
    /// (`tasks/NO-005.md` §1.2 "화면 동작 동일 유지").
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        folderId: String? = nil,
        title: String = "Untitled",
        schemaVersion: Int = 1,
        revision: Int = 1,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.title = title
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
