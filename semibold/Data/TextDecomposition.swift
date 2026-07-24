import Foundation

/// Pulls a `DocumentBlock`'s rich text apart into the new schema's
/// `TextItem.plainText` plus one `TextMark` per inline mark
/// `BlockContent` recorded (`tasks/NO-005.md` §4.2, `STORAGE_ARCHITECTURE.md`
/// §3.4). Used by `DocumentBlockMigrationPolicy` — kept as a standalone,
/// side-effect-free function so it's easy to reason about (and later
/// test) independently of the Core Data migration machinery around it.
struct TextDecomposition {
    /// One inline mark, in the shape `TextMark` stores it
    /// (`STORAGE_ARCHITECTURE.md` §3.4: `start_offset`/`end_offset` are
    /// UTF-16 code unit offsets into `plainText`, per `tasks/NO-005.md`
    /// §2.3).
    struct Mark {
        var startOffset: Int
        var endOffset: Int
        var markType: String
        var valueMode: String?
        var valueText: String?
    }

    var plainText: String
    var marks: [Mark]

    /// Builds a `TextDecomposition` from `content`'s rich-text spans.
    ///
    /// Each `RichTextSpan.text` still carries its literal Markdown
    /// delimiters today (`"**bold**"`, not `"bold"` —
    /// `BlockContent+InlineMarks.swift`'s deliberate deviation, kept so
    /// the live editor can round-trip raw typed Markdown). The new
    /// schema's `plain_text` + offset-based `TextMark`s expect the
    /// opposite: clean rendered text with formatting recorded as ranges
    /// over it (`STORAGE_ARCHITECTURE.md` §4's worked example has no
    /// `**`/`` ` `` characters in `plain_text`) — so this strips each
    /// span's delimiters back off while building `plainText`, and records
    /// the mark's range over the stripped text. This keeps the migrated
    /// content re-exportable to the same Markdown later (wrap the marked
    /// range back in its delimiter), which is what `tasks/NO-005.md` §4.2's
    /// pre/post export diff check verifies.
    static func decompose(_ content: BlockContent) -> TextDecomposition {
        var plainText = ""
        var marks: [Mark] = []

        for span in content.text {
            let startOffset = plainText.utf16.count
            let (visibleText, mark) = strip(span)
            plainText += visibleText
            let endOffset = plainText.utf16.count

            if let mark {
                marks.append(
                    Mark(
                        startOffset: startOffset,
                        endOffset: endOffset,
                        markType: mark.markType,
                        valueMode: mark.valueMode,
                        valueText: mark.valueText
                    )
                )
            }
        }

        return TextDecomposition(plainText: plainText, marks: marks)
    }

    /// One span's rendered text (Markdown delimiters removed) plus the
    /// `TextMark` it should produce, if any.
    private struct StrippedMark {
        var markType: String
        var valueMode: String?
        var valueText: String?
    }

    /// Strips `span`'s Markdown delimiters and describes the mark it
    /// represents, if it has one.
    ///
    /// Only looks at `span.marks`'s first entry: `RichTextSpan.parse`
    /// (the only place that currently produces marked spans) always
    /// assigns exactly one mark per span, so this is exhaustive for every
    /// span this migration will actually see. A span with more than one
    /// mark (not produced by any code today) would silently keep only
    /// the first — flagged in this migration's report rather than guessed
    /// at further, since there's no existing data shape to validate a
    /// multi-mark policy against.
    private static func strip(_ span: RichTextSpan) -> (text: String, mark: StrippedMark?) {
        guard let marks = span.marks, let primary = marks.first else {
            return (span.text, nil)
        }

        let markType = primary.rawValue
        let visibleText: String
        var valueMode: String?
        var valueText: String?

        switch primary {
        case .link:
            // `RichTextSpan.parse` keeps the full "[label](url)" syntax as
            // `text`; `href` already holds the URL separately, so only
            // the bracketed label needs pulling out here.
            visibleText = linkLabel(fromMarkdown: span.text) ?? span.text
            valueMode = "url"
            valueText = span.href
        case .bold:
            visibleText = trimDelimiter("**", from: span.text)
        case .italic:
            visibleText = trimDelimiter("*", from: span.text)
        case .strike:
            visibleText = trimDelimiter("~~", from: span.text)
        case .inlineCode:
            visibleText = trimDelimiter("`", from: span.text)
        }

        return (visibleText, StrippedMark(markType: markType, valueMode: valueMode, valueText: valueText))
    }

    /// Removes a matching `delimiter` from both ends of `text` if present
    /// on both, otherwise returns `text` unchanged (defensive — every
    /// span carrying `marks` is expected to be delimiter-wrapped by
    /// `RichTextSpan.parse`, but this avoids corrupting older/malformed
    /// `contentJSON` that doesn't match that shape).
    private static func trimDelimiter(_ delimiter: String, from text: String) -> String {
        guard text.hasPrefix(delimiter), text.hasSuffix(delimiter), text.count >= delimiter.count * 2 else {
            return text
        }
        let start = text.index(text.startIndex, offsetBy: delimiter.count)
        let end = text.index(text.endIndex, offsetBy: -delimiter.count)
        guard start <= end else { return text }
        return String(text[start..<end])
    }

    /// Extracts `label` out of a `"[label](url)"` string. Returns `nil`
    /// if `markdown` doesn't match that shape (falls back to keeping the
    /// raw text, see `strip(_:)`).
    private static func linkLabel(fromMarkdown markdown: String) -> String? {
        guard markdown.hasPrefix("["), let closeBracket = markdown.firstIndex(of: "]") else { return nil }
        let start = markdown.index(after: markdown.startIndex)
        guard start <= closeBracket else { return nil }
        return String(markdown[start..<closeBracket])
    }
}
