import Foundation

/// One content element within a document — a paragraph, heading, list
/// item, image, etc.
///
/// A `DocumentItem` only carries a document's *structure* (its position
/// and place in the hierarchy); the actual content lives in a
/// type-specific detail record keyed by this item's `id`
/// (`TextContent` for `contentType == "text"`, `MediaContent` for
/// `contentType == "media"`, …) — `DOCUMENT_MODEL.md` §2.2 "구조와 실제
/// 콘텐츠의 분리". Items form a tree via `parentItemId` (`nil` for a
/// top-level item) and are ordered among their siblings by `orderKey`.
struct DocumentItem: Identifiable, Hashable, Codable {
    var id: String
    var documentId: String
    var parentItemId: String?
    /// The kind of content this item holds (`"text"`, `"media"`, or a
    /// future type). Kept as a plain string rather than a closed enum so
    /// an item whose `contentType` this build doesn't recognize yet can
    /// still be preserved read-only instead of failing to decode
    /// (`DOCUMENT_MODEL.md` §4.5).
    var contentType: String
    /// This item's position among siblings under the same
    /// `parentItemId`, as a string-based fractional index — supports
    /// inserting between two existing items without renumbering anything
    /// else (`tasks/NO-005.md` §2.2).
    var orderKey: String
    var revision: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        documentId: String,
        parentItemId: String? = nil,
        contentType: String = "text",
        orderKey: String,
        revision: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.documentId = documentId
        self.parentItemId = parentItemId
        self.contentType = contentType
        self.orderKey = orderKey
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
