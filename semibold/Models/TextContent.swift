import Foundation

/// The text-specific detail record for a `DocumentItem` whose
/// `contentType` is `"text"` — one-to-one with its owning item via
/// `itemId` (`tasks/NO-005.md` §3 "TextItem (1:1 with DocumentItem, item_id
/// 기준)").
///
/// Not every field applies to every `textKind` — e.g. `headingLevel` only
/// means something for a heading, `isChecked` only for a checklist item
/// (`DOCUMENT_MODEL.md` §4.1).
struct TextContent: Identifiable, Hashable, Codable {
    var itemId: String
    /// The kind of text element this is (e.g. `"paragraph"`, `"heading"`,
    /// `"quote"`, `"checklist"`, `"bulleted_list_item"`,
    /// `"numbered_list_item"`, `"code_block"`, `"divider"`, `"unknown"`
    /// for content this build doesn't recognize). Kept as a plain string
    /// rather than a closed enum, since `DOCUMENT_MODEL.md` §4.1's
    /// "recommended" list isn't exhaustive, and a closed enum would break
    /// the "preserve unrecognized content" guarantee in §4.5.
    var textKind: String
    var plainText: String
    /// The heading level (e.g. 1-3), set only when `textKind == "heading"`.
    var headingLevel: Int?
    /// The paragraph-level text alignment, when the user has set one
    /// other than the default.
    var alignment: String?
    /// Whether this item's task is marked done, set only when
    /// `textKind == "checklist"`.
    var isChecked: Bool?
    /// A user-defined style override, if this text element uses one
    /// instead of its `textKind`'s default appearance.
    var customStyleId: String?

    var id: String { itemId }

    init(
        itemId: String,
        textKind: String,
        plainText: String = "",
        headingLevel: Int? = nil,
        alignment: String? = nil,
        isChecked: Bool? = nil,
        customStyleId: String? = nil
    ) {
        self.itemId = itemId
        self.textKind = textKind
        self.plainText = plainText
        self.headingLevel = headingLevel
        self.alignment = alignment
        self.isChecked = isChecked
        self.customStyleId = customStyleId
    }
}
