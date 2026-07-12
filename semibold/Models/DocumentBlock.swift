import Foundation

/// The kind of content a `DocumentBlock` holds, mirroring the writing
/// elements the editor offers (paragraph, heading, lists, quote, code,
/// divider, …).
enum BlockType: String, Codable, CaseIterable {
    case paragraph
    case heading
    case bulletedListItem = "bulleted_list_item"
    case numberedListItem = "numbered_list_item"
    case checklistItem = "checklist_item"
    case blockquote
    case codeBlock = "code_block"
    case divider
}

/// One paragraph/heading/list item/etc. within a document.
///
/// Blocks form a tree via `parentId` (e.g. list items nested under a
/// list) and are ordered by `sortOrder` within their parent. `contentJSON`
/// holds the block's structured content (rich text spans, code, …) as
/// JSON, while `markdownSource` keeps the Markdown the user typed for
/// round-tripping.
struct DocumentBlock: Identifiable, Equatable, Codable {
    var id: String
    var documentId: String
    var parentId: String?
    var sortOrder: Int
    var type: BlockType
    var contentJSON: String
    var markdownSource: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        documentId: String,
        parentId: String? = nil,
        sortOrder: Int = 0,
        type: BlockType,
        contentJSON: String,
        markdownSource: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.documentId = documentId
        self.parentId = parentId
        self.sortOrder = sortOrder
        self.type = type
        self.contentJSON = contentJSON
        self.markdownSource = markdownSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
