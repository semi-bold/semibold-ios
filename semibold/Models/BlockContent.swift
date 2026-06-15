import Foundation

/// A run of text within a block's content, carrying any inline formatting
/// marks applied to it (PLANNING/`tasks/NO-001.md` §8.1 `RichTextSpan`).
///
/// Marks (`bold`, `italic`, `strike`, `inline_code`, `link`) and `href` are
/// `markdown-phase4` follow-up scope (AC6) — for now every span is plain
/// text, but the type is named and shaped to match §8.1 so that work can
/// extend it without renaming.
struct RichTextSpan: Codable, Equatable {
    var text: String
}

/// The structured content stored in a `DocumentBlock`'s `contentJSON`,
/// mirroring §8.1's `BlockContent` union. Each case matches one
/// `BlockType` and round-trips through `contentJSON` via
/// `BlockContent.encodeJSON()` / `BlockContent.decode(from:type:)`.
///
/// Only the shapes this AC needs (`paragraph`, `heading`) are modeled so
/// far — list/checklist/blockquote/code/divider shapes are added as later
/// `markdown-phase4` acceptance criteria implement those conversions.
enum BlockContent: Equatable {
    case paragraph(ParagraphContent)
    case heading(HeadingContent)

    /// The plain text shared by every case modeled so far. Block types
    /// without a `text` field (e.g. a future `code_block`/`divider`) would
    /// need their own accessor — not needed yet.
    var text: [RichTextSpan] {
        switch self {
        case .paragraph(let content): return content.text
        case .heading(let content): return content.text
        }
    }

    /// Encodes this content to the JSON stored in `contentJSON`.
    func encodeJSON() -> String {
        let data: Data?
        switch self {
        case .paragraph(let content): data = try? JSONEncoder().encode(content)
        case .heading(let content): data = try? JSONEncoder().encode(content)
        }
        guard let data, let json = String(data: data, encoding: .utf8) else {
            return "{\"type\":\"paragraph\",\"text\":[]}"
        }
        return json
    }

    /// Decodes `json` according to `type`, falling back to an empty
    /// paragraph if the JSON is missing or malformed (e.g. a block created
    /// before this shape existed).
    static func decode(from json: String, type: BlockType) -> BlockContent {
        let data = Data(json.utf8)
        switch type {
        case .heading:
            if let content = try? JSONDecoder().decode(HeadingContent.self, from: data) {
                return .heading(content)
            }
            return .heading(HeadingContent(level: 1, text: []))
        default:
            if let content = try? JSONDecoder().decode(ParagraphContent.self, from: data) {
                return .paragraph(content)
            }
            return .paragraph(ParagraphContent(text: []))
        }
    }

    /// Builds the `contentJSON` for a plain paragraph block holding
    /// `text` as a single unstyled span (§8.1 `{ type: "paragraph", text:
    /// RichTextSpan[] }`).
    static func paragraphJSON(text: String) -> String {
        BlockContent.paragraph(ParagraphContent(text: [RichTextSpan(text: text)])).encodeJSON()
    }

    /// Builds the `contentJSON` for a heading block at `level` (1-3)
    /// holding `text` as a single unstyled span (§8.1 `{ type: "heading",
    /// level: 1|2|3, text: RichTextSpan[] }`).
    static func headingJSON(level: Int, text: String) -> String {
        BlockContent.heading(HeadingContent(level: level, text: [RichTextSpan(text: text)])).encodeJSON()
    }
}

/// The `contentJSON` shape for a `.paragraph` block (§8.1
/// `{ type: "paragraph", text: RichTextSpan[] }`).
struct ParagraphContent: Codable, Equatable {
    var type = "paragraph"
    var text: [RichTextSpan]
}

/// The `contentJSON` shape for a `.heading` block (§8.1
/// `{ type: "heading", level: 1|2|3, text: RichTextSpan[] }`).
struct HeadingContent: Codable, Equatable {
    var type = "heading"
    var level: Int
    var text: [RichTextSpan]
}

extension DocumentBlock {
    /// The plain text the editor shows/edits for this block — the
    /// `contentJSON`'s text spans joined together, WITHOUT any Markdown
    /// prefix (e.g. a `# `/`## `/`### ` heading marker). `markdownSource`
    /// keeps the literal Markdown for round-tripping; this is what
    /// `ParagraphTextField`/`BlockRow` actually display and edit.
    var displayText: String {
        BlockContent.decode(from: contentJSON, type: type).text.map(\.text).joined()
    }

    /// The heading level (1-3) for a `.heading` block, or `nil` for any
    /// other block type.
    var headingLevel: Int? {
        guard case .heading(let content) = BlockContent.decode(from: contentJSON, type: type) else {
            return nil
        }
        return content.level
    }
}