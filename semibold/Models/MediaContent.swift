import Foundation

/// The media-specific detail record for a `DocumentItem` whose
/// `contentType` is `"media"` — one-to-one with its owning item via
/// `itemId` (`DOCUMENT_MODEL.md` §4.3 "Media Content").
///
/// The actual file data lives outside the document model in an `Asset`,
/// referenced here by `assetId`.
struct MediaContent: Identifiable, Hashable, Codable {
    var itemId: String
    var assetId: String
    /// The kind of media this is (e.g. `"image"`, `"video"`, `"audio"`,
    /// `"file"`).
    var mediaType: String
    /// Accessibility/alt text describing the media, if the user provided
    /// one.
    var altText: String?
    /// The `DocumentItem.id` of the text item used as this media's
    /// caption, if it has one.
    var captionItemId: String?
    var width: Double?
    var height: Double?

    var id: String { itemId }

    init(
        itemId: String,
        assetId: String,
        mediaType: String,
        altText: String? = nil,
        captionItemId: String? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) {
        self.itemId = itemId
        self.assetId = assetId
        self.mediaType = mediaType
        self.altText = altText
        self.captionItemId = captionItemId
        self.width = width
        self.height = height
    }
}
