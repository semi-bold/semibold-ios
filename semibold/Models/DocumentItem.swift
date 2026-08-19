import Foundation

/// One content element within a document — a paragraph, heading, list
/// item, image, etc.
///
/// A `DocumentItem` only carries a document's *structure* (its position
/// and place in the hierarchy); the actual content lives in a
/// type-specific detail record keyed by this item's `id`
/// (`TextContent` for `contentType == "text"`, `MediaContent` for
/// `contentType == "media"`, …) — `DOCUMENT_MODEL.md` §2.2 "구조와 실제
/// 콘텐츠의 분리". Items are ordered by `orderKey`; nesting (currently
/// only ever used by list-kind items, `tasks/NO-009.md` §3.1) is `depth`
/// + `listGroupId`, not a parent reference — see `ListGroup`'s doc
/// comment.
struct DocumentItem: Identifiable, Hashable, Codable {
    var id: String
    var documentId: String
    /// Nesting level (0 = top-level). Stored, not derived — unlike a
    /// parent-chain walk, indent/outdent must keep every affected item's
    /// own `depth` (including any of its descendants') in sync
    /// explicitly (`DetailViewModel.indentBlock(_:)`/`.outdentBlock(_:)`).
    /// Always `0` for a non-list item.
    var depth: Int
    /// The `ListGroup` this item belongs to, or `nil` for a non-list
    /// item. Members of one group are what "select/collapse/delete this
    /// whole list" future features would operate on together.
    var listGroupId: String?
    /// The kind of content this item holds (`"text"`, `"media"`, or a
    /// future type). Kept as a plain string rather than a closed enum so
    /// an item whose `contentType` this build doesn't recognize yet can
    /// still be preserved read-only instead of failing to decode
    /// (`DOCUMENT_MODEL.md` §4.5).
    var contentType: String
    /// This item's position among every item in the document, as a
    /// string-based fractional index — supports inserting between two
    /// existing items without renumbering anything else
    /// (`tasks/NO-005.md` §2.2).
    var orderKey: String
    var revision: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        documentId: String,
        depth: Int = 0,
        listGroupId: String? = nil,
        contentType: String = "text",
        orderKey: String,
        revision: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.documentId = documentId
        self.depth = depth
        self.listGroupId = listGroupId
        self.contentType = contentType
        self.orderKey = orderKey
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
