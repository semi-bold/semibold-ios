import Foundation
import UniformTypeIdentifiers

/// The app's own, lossless clipboard representation for a copied block
/// range — carried alongside a Markdown fallback (`tasks/NO-010.md`
/// §3.1 "클립보드 이중 표현"). Pasting back into this app decodes this
/// payload directly instead of round-tripping through Markdown, so any
/// block kind the data model supports survives copy/paste byte-for-byte
/// regardless of whether Markdown syntax can express it.
///
/// One array per DB table, mirroring the app's existing structure/content
/// split (`DocumentItem` + its `TextContent`/`ListGroup` detail records,
/// plus any `TextMark`s on the copied text) rather than a single combined
/// tree.
struct BlockClipboardPayload: Codable, Hashable {
    /// Bumped only for a genuinely incompatible payload shape change, so
    /// a future reader can recognize a version it can't decode and fall
    /// back to the Markdown representation instead. Not read or branched
    /// on yet — always encoded as `1` — but the field must exist now so
    /// it carries meaning once that day comes
    /// (`tasks/NO-010.md` §3.1 "스키마 확장 대비").
    var schemaVersion: Int
    var items: [DocumentItem]
    var textContents: [TextContent]
    var listGroups: [ListGroup]
    var textMarks: [TextMark]

    init(
        schemaVersion: Int = BlockClipboardPayload.currentSchemaVersion,
        items: [DocumentItem],
        textContents: [TextContent],
        listGroups: [ListGroup],
        textMarks: [TextMark]
    ) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.textContents = textContents
        self.listGroups = listGroups
        self.textMarks = textMarks
    }

    /// Decodes leniently: a clipboard payload written by a future app
    /// version that has added a new array field (or, symmetrically, one
    /// read by an older app version that doesn't know about one of
    /// today's fields) must not fail to decode just because one of these
    /// keys is missing — it should decode with that field as an empty
    /// array instead (`tasks/NO-010.md` §3.1, 배열 필드 규칙).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        items = try container.decodeIfPresent([DocumentItem].self, forKey: .items) ?? []
        textContents = try container.decodeIfPresent([TextContent].self, forKey: .textContents) ?? []
        listGroups = try container.decodeIfPresent([ListGroup].self, forKey: .listGroups) ?? []
        textMarks = try container.decodeIfPresent([TextMark].self, forKey: .textMarks) ?? []
    }
}

extension BlockClipboardPayload {
    /// The current, always-encoded `schemaVersion` value — bump this
    /// when the payload shape changes incompatibly.
    static let currentSchemaVersion = 1

    /// The custom UTType clipboard writes/reads use to recognize this
    /// app's own lossless block representation ahead of the Markdown
    /// fallback (`project.yml`'s `UTExportedTypeDeclarations`).
    static let utType = UTType(exportedAs: "com.semibold.blocks-payload")

    /// Packages a selected block range's already-split-out model arrays
    /// into one encodable payload. Callers (the copy flow) decide which
    /// items belong in each array — this just wraps them.
    static func encode(
        items: [DocumentItem],
        textContents: [TextContent],
        listGroups: [ListGroup],
        textMarks: [TextMark]
    ) throws -> Data {
        let payload = BlockClipboardPayload(
            items: items,
            textContents: textContents,
            listGroups: listGroups,
            textMarks: textMarks
        )
        return try JSONEncoder().encode(payload)
    }

    /// Restores the payload a clipboard write's JSON data was built from
    /// (the paste flow's counterpart to `encode`) — `items`/`textContents`/
    /// `listGroups`/`textMarks` are the four model arrays. Returns
    /// `BlockClipboardPayload` itself rather than a tuple: it already *is*
    /// exactly those four arrays, and a 4-member tuple return trips
    /// SwiftLint's `large_tuple` rule.
    static func decode(_ data: Data) throws -> BlockClipboardPayload {
        try JSONDecoder().decode(BlockClipboardPayload.self, from: data)
    }
}
