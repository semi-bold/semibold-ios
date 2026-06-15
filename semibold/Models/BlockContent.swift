import Foundation

/// An inline formatting mark that can be applied to a `RichTextSpan` (§8.1
/// `RichTextSpan.marks`) — bold, italic, strikethrough, inline code, or a
/// link. `link` is recorded alongside `RichTextSpan.href`, which carries the
/// link's destination URL.
enum RichTextMark: String, Codable, Equatable {
    case bold
    case italic
    case strike
    case inlineCode = "inline_code"
    case link
}

/// A run of text within a block's content, carrying any inline formatting
/// marks applied to it (PLANNING/`tasks/NO-001.md` §8.1 `RichTextSpan`).
///
/// `marks`/`href` are `Optional` so `contentJSON` written before
/// `markdown-phase4` AC6 (encoded as `{"text": "..."}` with neither key)
/// still decodes correctly — `Codable` leaves an `Optional` property `nil`
/// when its key is missing, rather than failing to decode.
struct RichTextSpan: Codable, Equatable {
    var text: String
    /// Inline formatting marks applied to `text` (§7.1/§7.3's `**bold**`,
    /// `*italic*`, `~~strike~~`, `` `code` ``, `[text](url)` syntax), or
    /// `nil` for a plain unstyled span.
    var marks: [RichTextMark]?
    /// The link destination for a span whose `marks` includes `.link`
    /// (§7.1/§7.3's `[text](url)` syntax), or `nil` for a non-link span.
    var href: String?

    init(text: String, marks: [RichTextMark]? = nil, href: String? = nil) {
        self.text = text
        self.marks = marks
        self.href = href
    }
}

/// The structured content stored in a `DocumentBlock`'s `contentJSON`,
/// mirroring §8.1's `BlockContent` union. Each case matches one
/// `BlockType` and round-trips through `contentJSON` via
/// `BlockContent.encodeJSON()` / `BlockContent.decode(from:type:)`.
///
/// Only the shapes implemented so far (`paragraph`, `heading`,
/// `bulletedListItem`, `numberedListItem`, `checklistItem`, `blockquote`,
/// `codeBlock`) are modeled as real cases — `divider` (which has no
/// content fields at all per §8.1) falls back to `.paragraph` in
/// `decode(from:type:)` until a later AC needs it.
enum BlockContent: Equatable {
    case paragraph(ParagraphContent)
    case heading(HeadingContent)
    case bulletedListItem(ListItemContent)
    case numberedListItem(ListItemContent)
    case checklistItem(ChecklistItemContent)
    case blockquote(BlockquoteContent)
    case codeBlock(CodeBlockContent)

    /// The plain text shared by every case modeled so far. A `.codeBlock`'s
    /// `code` (plain text, not rich text per §8.1) is wrapped in a single
    /// unstyled `RichTextSpan` so this stays a uniform accessor —
    /// `DocumentBlock.displayText`'s `.text.map(\.text).joined()` then
    /// returns `code` unchanged without needing its own case.
    var text: [RichTextSpan] {
        switch self {
        case .paragraph(let content): return content.text
        case .heading(let content): return content.text
        case .bulletedListItem(let content): return content.text
        case .numberedListItem(let content): return content.text
        case .checklistItem(let content): return content.text
        case .blockquote(let content): return content.text
        case .codeBlock(let content): return [RichTextSpan(text: content.code)]
        }
    }

    /// Encodes this content to the JSON stored in `contentJSON`.
    func encodeJSON() -> String {
        let data: Data?
        switch self {
        case .paragraph(let content): data = try? JSONEncoder().encode(content)
        case .heading(let content): data = try? JSONEncoder().encode(content)
        case .bulletedListItem(let content): data = try? JSONEncoder().encode(content)
        case .numberedListItem(let content): data = try? JSONEncoder().encode(content)
        case .checklistItem(let content): data = try? JSONEncoder().encode(content)
        case .blockquote(let content): data = try? JSONEncoder().encode(content)
        case .codeBlock(let content): data = try? JSONEncoder().encode(content)
        }
        guard let data, let json = String(data: data, encoding: .utf8) else {
            return "{\"type\":\"paragraph\",\"text\":[]}"
        }
        return json
    }

    /// Decodes `json` according to `type`, falling back to an empty
    /// paragraph if the JSON is missing or malformed (e.g. a block created
    /// before this shape existed). `.divider` (no content fields modeled
    /// yet) also falls back to `.paragraph` until a later AC adds its case.
    static func decode(from json: String, type: BlockType) -> BlockContent {
        let data = Data(json.utf8)
        switch type {
        case .paragraph:
            if let content = try? JSONDecoder().decode(ParagraphContent.self, from: data) {
                return .paragraph(content)
            }
            return .paragraph(ParagraphContent(text: []))
        case .heading:
            if let content = try? JSONDecoder().decode(HeadingContent.self, from: data) {
                return .heading(content)
            }
            return .heading(HeadingContent(level: 1, text: []))
        case .bulletedListItem:
            if let content = try? JSONDecoder().decode(ListItemContent.self, from: data) {
                return .bulletedListItem(content)
            }
            return .bulletedListItem(ListItemContent(type: "bulleted_list_item", text: []))
        case .numberedListItem:
            if let content = try? JSONDecoder().decode(ListItemContent.self, from: data) {
                return .numberedListItem(content)
            }
            return .numberedListItem(ListItemContent(type: "numbered_list_item", text: []))
        case .checklistItem:
            if let content = try? JSONDecoder().decode(ChecklistItemContent.self, from: data) {
                return .checklistItem(content)
            }
            return .checklistItem(ChecklistItemContent(checked: false, text: []))
        case .blockquote:
            if let content = try? JSONDecoder().decode(BlockquoteContent.self, from: data) {
                return .blockquote(content)
            }
            return .blockquote(BlockquoteContent(text: []))
        case .codeBlock:
            if let content = try? JSONDecoder().decode(CodeBlockContent.self, from: data) {
                return .codeBlock(content)
            }
            return .codeBlock(CodeBlockContent(language: nil, code: ""))
        case .divider:
            if let content = try? JSONDecoder().decode(ParagraphContent.self, from: data) {
                return .paragraph(content)
            }
            return .paragraph(ParagraphContent(text: []))
        }
    }

    /// Builds the `contentJSON` for a plain paragraph block, parsing `text`
    /// for inline Markdown marks (§7.1/§7.3's `**bold**`, `*italic*`,
    /// `~~strike~~`, `` `code` ``, `[text](url)` syntax) into `[RichTextSpan]`
    /// (§8.1 `{ type: "paragraph", text: RichTextSpan[] }`).
    static func paragraphJSON(text: String) -> String {
        BlockContent.paragraph(ParagraphContent(text: RichTextSpan.parse(markdownText: text))).encodeJSON()
    }

    /// Builds the `contentJSON` for a heading block at `level` (1-3),
    /// parsing `text` for inline Markdown marks into `[RichTextSpan]` (§8.1
    /// `{ type: "heading", level: 1|2|3, text: RichTextSpan[] }`).
    static func headingJSON(level: Int, text: String) -> String {
        BlockContent.heading(HeadingContent(level: level, text: RichTextSpan.parse(markdownText: text))).encodeJSON()
    }

    /// Builds the `contentJSON` for a bulleted (unordered) list item,
    /// parsing `text` for inline Markdown marks into `[RichTextSpan]` (§8.1
    /// `{ type: "bulleted_list_item", text: RichTextSpan[] }`).
    static func bulletedListItemJSON(text: String) -> String {
        BlockContent.bulletedListItem(
            ListItemContent(type: "bulleted_list_item", text: RichTextSpan.parse(markdownText: text))
        ).encodeJSON()
    }

    /// Builds the `contentJSON` for a numbered (ordered) list item, parsing
    /// `text` for inline Markdown marks into `[RichTextSpan]` (§8.1
    /// `{ type: "numbered_list_item", text: RichTextSpan[] }`).
    static func numberedListItemJSON(text: String) -> String {
        BlockContent.numberedListItem(
            ListItemContent(type: "numbered_list_item", text: RichTextSpan.parse(markdownText: text))
        ).encodeJSON()
    }

    /// Builds the `contentJSON` for a checklist item, parsing `text` for
    /// inline Markdown marks into `[RichTextSpan]`, with `checked` as its
    /// current done/not-done state (§8.1 `{ type: "checklist_item", checked:
    /// boolean, text: RichTextSpan[] }`).
    static func checklistItemJSON(checked: Bool, text: String) -> String {
        BlockContent.checklistItem(
            ChecklistItemContent(checked: checked, text: RichTextSpan.parse(markdownText: text))
        ).encodeJSON()
    }

    /// Builds the `contentJSON` for a blockquote block, parsing `text` for
    /// inline Markdown marks into `[RichTextSpan]` (§8.1
    /// `{ type: "blockquote", text: RichTextSpan[] }`).
    static func blockquoteJSON(text: String) -> String {
        BlockContent.blockquote(BlockquoteContent(text: RichTextSpan.parse(markdownText: text))).encodeJSON()
    }

    /// Builds the `contentJSON` for a code block holding `code` as plain
    /// text and an optional `language` identifier (§8.1
    /// `{ type: "code_block", language?: string, code: string }`).
    /// `language` is `nil` when the user typed a bare ` ``` ` fence with no
    /// language identifier after it.
    static func codeBlockJSON(language: String?, code: String) -> String {
        BlockContent.codeBlock(CodeBlockContent(language: language, code: code)).encodeJSON()
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

/// The `contentJSON` shape shared by `.bulletedListItem` and
/// `.numberedListItem` blocks (§8.1 `{ type: "bulleted_list_item" |
/// "numbered_list_item", text: RichTextSpan[] }`). `type` distinguishes
/// the two on disk; `BlockContent` wraps this in the matching case based
/// on the block's `BlockType`.
struct ListItemContent: Codable, Equatable {
    var type: String
    var text: [RichTextSpan]
}

/// The `contentJSON` shape for a `.checklistItem` block (§8.1
/// `{ type: "checklist_item", checked: boolean, text: RichTextSpan[] }`).
/// `checked` tracks whether the task has been marked done, toggled by
/// tapping the checklist item's checkbox (§7.1).
struct ChecklistItemContent: Codable, Equatable {
    var type = "checklist_item"
    var checked: Bool
    var text: [RichTextSpan]
}

/// The `contentJSON` shape for a `.blockquote` block (§8.1
/// `{ type: "blockquote", text: RichTextSpan[] }`). Identical in shape to
/// `ParagraphContent`/`ListItemContent`, but kept as its own type (rather
/// than reused) so each `BlockContent` case's `type` literal matches its
/// own `BlockType` — following `HeadingContent`/`ChecklistItemContent`'s
/// precedent of a dedicated struct per case.
struct BlockquoteContent: Codable, Equatable {
    var type = "blockquote"
    var text: [RichTextSpan]
}

/// The `contentJSON` shape for a `.codeBlock` block (§8.1
/// `{ type: "code_block", language?: string, code: string }`). Unlike
/// every other case so far, a code block's `code` is plain text — not
/// `RichTextSpan[]` — since code isn't subject to inline formatting marks
/// (bold/italic/etc.). `language` is the identifier typed after the
/// opening ` ``` ` fence (e.g. `"swift"`), or `nil` if the fence had no
/// language.
struct CodeBlockContent: Codable, Equatable {
    var type = "code_block"
    var language: String?
    var code: String
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

    /// The number shown before a `.numberedListItem` block's text (e.g.
    /// `1` for `"1. item"`), or `nil` for any other block type.
    ///
    /// Read from `markdownSource`'s leading `<n>.` rather than
    /// `contentJSON`, since `ListItemContent` doesn't carry the number
    /// itself (§8.1's `numbered_list_item` shape is `{ type, text }` only).
    /// Defaults to 1 if `markdownSource` is missing/malformed.
    /// Auto-incrementing this number across a list's items is a
    /// `quality-phase5` follow-up — each item currently keeps the number
    /// the user originally typed.
    var numberedListNumber: Int? {
        guard type == .numberedListItem else { return nil }
        return BlockContent.leadingNumber(forMarkdownSource: markdownSource)
    }

    /// Whether a `.checklistItem` block's task is marked done, read from
    /// `contentJSON.checked` (§7.1's checklist toggle). `false` for any
    /// other block type, or for a `.checklistItem` whose `contentJSON` is
    /// missing/malformed.
    var isChecked: Bool {
        guard case .checklistItem(let content) = BlockContent.decode(from: contentJSON, type: type) else {
            return false
        }
        return content.checked
    }

    /// The language identifier shown above a `.codeBlock` block's code
    /// (e.g. `"swift"` for ` ```swift `), read from `contentJSON.language`.
    /// `nil` for any other block type, or for a `.codeBlock` whose fence had
    /// no language identifier.
    var codeLanguage: String? {
        guard case .codeBlock(let content) = BlockContent.decode(from: contentJSON, type: type) else {
            return nil
        }
        return content.language
    }
}

extension BlockContent {
    /// Reads the leading `<n>` out of a `markdownSource` string
    /// (`"<n>. ..."`), defaulting to 1 if it's missing/malformed. Shared by
    /// `DocumentBlock.numberedListNumber` and
    /// `DetailViewModel`'s numbered-list-item editing path.
    static func leadingNumber(forMarkdownSource markdownSource: String?) -> Int {
        guard let markdownSource else { return 1 }
        var digits = ""
        for character in markdownSource {
            if character.isNumber {
                digits.append(character)
            } else {
                break
            }
        }
        return Int(digits) ?? 1
    }
}
