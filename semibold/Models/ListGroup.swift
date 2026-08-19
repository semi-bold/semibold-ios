import Foundation

/// Ties together the `DocumentItem`s that make up one outline of list
/// items (bulleted/numbered/checklist) — `tasks/NO-009.md` §3.1. Each
/// member `DocumentItem` stores its own `depth`/`listGroupId`; nothing
/// here derives a member's position from anything else, so no parent
/// lookup is ever needed to answer "is this item nested?" or "can it
/// outdent?" (`DetailViewModel.listNestingInfo(forItemId:)`).
///
/// Carries no content of its own — like `TextContent`, it's a detail
/// record with no independent lifecycle: when its last live member
/// leaves (converted away or deleted), the group row itself is hard
/// deleted rather than soft deleted (`DetailViewModel`'s list-mutation
/// methods).
struct ListGroup: Identifiable, Hashable, Codable {
    var id: String
    var documentId: String
    /// One of `TextItemKind.listKinds` — an informational cache of the
    /// group's list kind, not authoritative (each member's own
    /// `TextContent.textKind` is what every rule actually checks). Not
    /// read anywhere yet; kept for future group-level features (e.g. a
    /// "this whole list" bulk action) that need a kind without walking
    /// every member.
    var listType: String

    init(id: String = UUID().uuidString, documentId: String, listType: String) {
        self.id = id
        self.documentId = documentId
        self.listType = listType
    }
}
