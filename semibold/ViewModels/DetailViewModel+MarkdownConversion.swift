import Foundation

/// Markdown prefix-detection and `markdownSource` helpers for
/// `DetailViewModel.updateBlockText`'s block-type conversions
/// (`markdown-phase4` AC1-AC5: heading/list/checklist/blockquote/code
/// block).
///
/// Split out of `DetailViewModel.swift` (which had grown past SwiftLint's
/// `file_length` warning threshold) once AC4 (blockquote) added another
/// conversion — keeps the view-model's create/edit/split/merge/reorder
/// logic in one file and all "does this typed text match a Markdown
/// prefix, and what should the block become" logic in this one. Each
/// helper here is `internal` (not `private`) only because Swift's
/// `private` is file-scoped and `updateBlockText` lives in the other file
/// — none of this is part of the app's public API.
extension DetailViewModel {
    /// A detected Markdown heading prefix, ready to apply to a block.
    struct HeadingConversion {
        /// The heading level (1-3), from the number of leading `#`s.
        let level: Int
        /// The text after the prefix, shown in the editor and stored as
        /// the heading's `RichTextSpan`.
        let text: String
        /// The full literal Markdown (`"# Title"`, …) to keep as
        /// `markdownSource` for round-tripping (§8.1 comment).
        let markdownSource: String
    }

    /// Detects whether `text` (the block's full text right after this
    /// keystroke) now starts with a complete Markdown heading prefix —
    /// 1-3 `#`s followed by a space — per §7.1/§7.3's
    /// `# Title` / `## Title` / `### Title` → Heading 1/2/3 syntax.
    ///
    /// Returns `nil` if `text` doesn't start with such a prefix, so the
    /// caller leaves the block as a paragraph.
    static func headingConversion(forTypedText text: String) -> HeadingConversion? {
        var hashCount = 0
        for character in text {
            if character == "#" {
                hashCount += 1
                if hashCount > 3 { return nil }
            } else {
                break
            }
        }
        guard hashCount >= 1, hashCount <= 3 else { return nil }

        let afterHashes = text.dropFirst(hashCount)
        guard afterHashes.first == " " else { return nil }

        let remainder = String(afterHashes.dropFirst())
        return HeadingConversion(level: hashCount, text: remainder, markdownSource: text)
    }

    /// Reads the `level` (1-3) out of a `.heading` block's `contentJSON`,
    /// defaulting to 1 if it's missing/malformed.
    static func headingLevel(forContentJSON json: String) -> Int {
        if case .heading(let content) = BlockContent.decode(from: json, type: .heading) {
            return content.level
        }
        return 1
    }

    /// Rebuilds the literal Markdown `markdownSource` (`"# Title"`, …) for
    /// a heading block at `level` holding `text`, so further edits keep
    /// round-tripping correctly.
    static func headingMarkdownSource(level: Int, text: String) -> String {
        String(repeating: "#", count: level) + " " + text
    }

    /// A detected Markdown list-item prefix (`- ` or `<n>. `), ready to
    /// apply to a block.
    struct ListConversion {
        /// The block type to convert to (`.bulletedListItem` or
        /// `.numberedListItem`).
        let type: BlockType
        /// The text after the prefix, shown in the editor and stored as
        /// the list item's `RichTextSpan`.
        let text: String
        /// The full literal Markdown (`"- item"`, `"1. item"`) to keep as
        /// `markdownSource` for round-tripping (§8.1 comment).
        let markdownSource: String

        /// Builds this conversion's `contentJSON` for `text`, matching
        /// `type`.
        func contentJSON(text: String) -> String {
            switch type {
            case .numberedListItem: return BlockContent.numberedListItemJSON(text: text)
            default: return BlockContent.bulletedListItemJSON(text: text)
            }
        }
    }

    /// Detects whether `text` (the block's full text right after this
    /// keystroke) now starts with a complete Markdown list-item prefix —
    /// `- ` (a hyphen + a space) for a bulleted list, or `<digits>. ` (one
    /// or more digits + a period + a space) for a numbered list — per
    /// §7.1/§7.3's `- item` / `1. item` → Bulleted/Numbered List syntax.
    ///
    /// Returns `nil` if `text` doesn't start with such a prefix, so the
    /// caller leaves the block as a paragraph. `"-item"` (no space) and
    /// `"-- item"` (a second `-` instead of the item text) don't match
    /// §7.3's literal `- item` syntax and so don't convert. `"- [ ] task"`/
    /// `"- [x] task"` (checklist syntax, §7.3) also don't match here —
    /// `checklistConversion(forTypedText:)` runs before this and takes
    /// precedence for those, so this never sees them in practice, but the
    /// explicit exclusion keeps this function correct on its own.
    /// `"> quote"` (blockquote syntax, §7.3) also doesn't match — it
    /// doesn't start with `-` or a digit, so no explicit exclusion is
    /// needed here.
    static func listConversion(forTypedText text: String) -> ListConversion? {
        if text.hasPrefix("- "), checklistConversion(forTypedText: text) == nil {
            let remainder = String(text.dropFirst(2))
            return ListConversion(type: .bulletedListItem, text: remainder, markdownSource: text)
        }

        var digitCount = 0
        for character in text {
            if character.isNumber {
                digitCount += 1
            } else {
                break
            }
        }
        guard digitCount >= 1 else { return nil }

        let afterDigits = text.dropFirst(digitCount)
        guard afterDigits.first == ".", afterDigits.dropFirst().first == " " else { return nil }

        let remainder = String(afterDigits.dropFirst(2))
        return ListConversion(type: .numberedListItem, text: remainder, markdownSource: text)
    }

    /// Rebuilds the literal Markdown `markdownSource` (`"- item"`) for a
    /// bulleted list item holding `text`, so further edits keep
    /// round-tripping correctly.
    static func bulletedListMarkdownSource(text: String) -> String {
        "- " + text
    }

    /// Rebuilds the literal Markdown `markdownSource` (`"<n>. item"`) for a
    /// numbered list item at `number` holding `text`, so further edits keep
    /// round-tripping correctly.
    static func numberedListMarkdownSource(number: Int, text: String) -> String {
        "\(number). " + text
    }

    /// A detected Markdown checklist-item prefix (`- [ ] ` or `- [x] `),
    /// ready to apply to a block.
    struct ChecklistConversion {
        /// Whether the task starts checked (`- [x] `) or unchecked
        /// (`- [ ] `).
        let checked: Bool
        /// The text after the prefix, shown in the editor and stored as
        /// the checklist item's `RichTextSpan`.
        let text: String
        /// The full literal Markdown (`"- [ ] task"`, `"- [x] task"`) to
        /// keep as `markdownSource` for round-tripping (§8.1 comment).
        let markdownSource: String
    }

    /// Detects whether `text` (the block's full text right after this
    /// keystroke) now starts with a complete Markdown checklist-item
    /// prefix — `- [ ] ` (unchecked) or `- [x] ` (checked) — per
    /// §7.1/§7.3's `- [ ] task` / `- [x] task` → Checklist syntax.
    ///
    /// Returns `nil` if `text` doesn't start with either prefix, so the
    /// caller leaves the block as a paragraph (or falls through to
    /// `listConversion(forTypedText:)`'s plain `- item` bulleted-list
    /// check). This check runs BEFORE that bulleted-list check in
    /// `updateBlockText`, so `"- [ ] task"`/`"- [x] task"` convert to
    /// `.checklistItem` rather than `.bulletedListItem` with a literal
    /// `"[ ] task"`/`"[x] task"` as their text.
    ///
    /// Per §7.3's literal syntax table, only the lowercase `x` marks a
    /// checked task — `"- [X] task"` (uppercase) and `"- [] task"` (no
    /// space inside the brackets) don't match either prefix and so don't
    /// convert.
    static func checklistConversion(forTypedText text: String) -> ChecklistConversion? {
        if text.hasPrefix("- [ ] ") {
            let remainder = String(text.dropFirst("- [ ] ".count))
            return ChecklistConversion(checked: false, text: remainder, markdownSource: text)
        }
        if text.hasPrefix("- [x] ") {
            let remainder = String(text.dropFirst("- [x] ".count))
            return ChecklistConversion(checked: true, text: remainder, markdownSource: text)
        }
        return nil
    }

    /// Rebuilds the literal Markdown `markdownSource` (`"- [ ] task"` /
    /// `"- [x] task"`) for a checklist item holding `text`, based on its
    /// current `checked` state, so further edits and toggles keep
    /// round-tripping correctly.
    static func checklistMarkdownSource(checked: Bool, text: String) -> String {
        (checked ? "- [x] " : "- [ ] ") + text
    }

    /// A detected Markdown blockquote prefix (`> `), ready to apply to a
    /// block.
    struct BlockquoteConversion {
        /// The text after the prefix, shown in the editor and stored as
        /// the blockquote's `RichTextSpan`.
        let text: String
        /// The full literal Markdown (`"> quote"`) to keep as
        /// `markdownSource` for round-tripping (§8.1 comment).
        let markdownSource: String
    }

    /// Detects whether `text` (the block's full text right after this
    /// keystroke) now starts with a complete Markdown blockquote prefix —
    /// `> ` (a greater-than sign + a space) — per §7.1/§7.3's `> quote` →
    /// Blockquote syntax.
    ///
    /// Returns `nil` if `text` doesn't start with that prefix, so the
    /// caller leaves the block as a paragraph. `">quote"` (no space) and
    /// `">> quote"` (second character is `>`, not a space) don't match
    /// §7.3's literal `> quote` syntax and so don't convert — same
    /// precedent as AC2's `"-- item"` not matching `"- "`. `> ` doesn't
    /// overlap with the `#`/`-`/`<n>. ` prefixes the other conversions
    /// check for, so there's no ordering ambiguity with them.
    static func blockquoteConversion(forTypedText text: String) -> BlockquoteConversion? {
        guard text.hasPrefix("> ") else { return nil }
        let remainder = String(text.dropFirst(2))
        return BlockquoteConversion(text: remainder, markdownSource: text)
    }

    /// Rebuilds the literal Markdown `markdownSource` (`"> quote"`) for a
    /// blockquote block holding `text`, so further edits keep
    /// round-tripping correctly.
    static func blockquoteMarkdownSource(text: String) -> String {
        "> " + text
    }

    /// A detected Markdown code-fence prefix (` ``` ` or ` ```<lang> `),
    /// ready to apply to a block.
    struct CodeBlockConversion {
        /// The language identifier typed right after the opening fence
        /// (e.g. `"swift"` for ` ```swift `), or `nil` if the fence had no
        /// language.
        let language: String?
        /// Any text typed after the fence (and its language, and the single
        /// space separating them, if present) — becomes the code block's
        /// initial `code` content. Empty if the user has only typed the
        /// fence (and language) so far.
        let code: String
    }

    /// Detects whether `text` (the block's full text right after this
    /// keystroke) now starts with a complete Markdown code-fence prefix —
    /// three backticks (` ``` `), optionally followed immediately by a
    /// language identifier — per §7.1/§7.3's ` ```lang ` → Code Block
    /// syntax.
    ///
    /// Returns `nil` if `text` doesn't start with three backticks, so the
    /// caller leaves the block as a paragraph. `` `` `` (two backticks) and
    /// `` ` `` (one backtick, §7.3's inline-code syntax) don't match and so
    /// don't convert here.
    ///
    /// Unlike AC1-AC4's single-line prefixes, a code block's content can
    /// span multiple lines and is normally closed by a separate ` ``` `
    /// fence on its own line — out of scope for this single-block editor
    /// (Enter creates a new block, not a newline within one). Conversion
    /// happens as soon as the opening fence (and optional language) is
    /// typed; any text typed after it on the same line becomes the initial
    /// `code`, and the closing fence isn't required for the conversion
    /// itself. Multi-line code editing within one block is a follow-up.
    static func codeBlockConversion(forTypedText text: String) -> CodeBlockConversion? {
        guard text.hasPrefix("```") else { return nil }
        let afterFence = text.dropFirst(3)

        var language = ""
        var remainder = Substring(afterFence)
        while let first = remainder.first, !first.isWhitespace {
            language.append(first)
            remainder = remainder.dropFirst()
        }
        if remainder.first == " " {
            remainder = remainder.dropFirst()
        }

        return CodeBlockConversion(language: language.isEmpty ? nil : language, code: String(remainder))
    }

    /// Rebuilds the literal Markdown `markdownSource` for a code block at
    /// `language` (or no language) holding `code`, keeping the closing
    /// fence so the block round-trips as ` ```<language>\n<code>\n``` `
    /// (§8.1 comment), rebuilt on every edit like AC1-AC4's
    /// `*MarkdownSource` builders.
    static func codeBlockMarkdownSource(language: String?, code: String) -> String {
        "```\(language ?? "")\n\(code)\n```"
    }
}
