import Foundation

/// An inline formatting mark applied to a range of a `TextContent`'s
/// `plainText` — bold, italic, a link, etc.
/// (`DOCUMENT_MODEL.md` §4.2 "Inline Mark").
///
/// `startOffset`/`endOffset` are UTF-16 code unit offsets into
/// `plainText` (`tasks/NO-005.md` §2.3) so they line up directly with
/// UIKit's `NSRange`-based text APIs without a conversion step. Several
/// `TextMark`s can cover overlapping ranges of the same item (e.g. bold
/// and a text color applied to the same span).
struct TextMark: Identifiable, Hashable, Codable {
    var id: String
    var itemId: String
    var startOffset: Int
    var endOffset: Int
    /// The kind of formatting this mark applies (e.g. `"bold"`,
    /// `"italic"`, `"underline"`, `"strike"`, `"inline_code"`, `"link"`,
    /// `"text_color"`, `"background_color"` — `DOCUMENT_MODEL.md` §4.2).
    var markType: String
    /// How `valueText` should be interpreted for mark types that carry an
    /// extra value (e.g. `"url"` for a `link` mark's destination). `nil`
    /// for mark types with no associated value (e.g. `bold`).
    var valueMode: String?
    /// The mark's associated value (e.g. a link's URL), interpreted per
    /// `valueMode`. `nil` for mark types with no associated value.
    var valueText: String?

    init(
        id: String = UUID().uuidString,
        itemId: String,
        startOffset: Int,
        endOffset: Int,
        markType: String,
        valueMode: String? = nil,
        valueText: String? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.markType = markType
        self.valueMode = valueMode
        self.valueText = valueText
    }
}
