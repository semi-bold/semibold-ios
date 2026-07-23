import Foundation

/// Rebuilds delimiter-literal Markdown text (`"**bold**"`, `` "`code`" ``,
/// `"[label](url)"`, …) from a clean `TextContent.plainText` plus the
/// `TextMark`s that describe its inline formatting — the inverse of
/// `TextDecomposition.decompose(_:)` (`semibold/Data/TextDecomposition.swift`,
/// brief 01), which strips a typed/imported block's literal delimiters out
/// of `RichTextSpan`s into clean `plainText` + offset-based `TextMark`s.
///
/// Needed because a MIGRATED document's `plainText` has already had its
/// delimiters stripped by that forward step — re-scanning it for delimiters
/// (`RichTextSpan.parse(markdownText:)`) finds nothing, so without this,
/// exporting a migrated document to Markdown silently drops all of its
/// bold/italic/strike/inline-code/link formatting. Used by
/// `MarkdownExporter.markdownLine(for:marks:numberedListNumber:)`
/// (`tasks/NO-005.md` §8 Phase 5, AC6) to reconstruct each item's
/// delimiter-literal Markdown line directly from `TextContent`/`TextMark`,
/// without going through `DocumentBlock`/`BlockContent` at all.
enum TextMarkdownReconstruction {
    /// Wraps each of `marks`' UTF-16 range of `plainText` back in its
    /// Markdown delimiter. Returns `plainText` unchanged when `marks` is
    /// empty — the "freshly typed, no marks recorded yet" case, whose
    /// `plainText` already keeps any delimiters the user literally typed
    /// (`BlockContent+InlineMarks.swift`'s deviation note) and needs no
    /// reconstruction.
    static func markdownText(plainText: String, marks: [TextMark]) -> String {
        guard !marks.isEmpty else { return plainText }

        let utf16Count = plainText.utf16.count
        let boundaries = self.boundaries(for: marks, utf16Count: utf16Count)
        guard !boundaries.isEmpty else { return plainText }

        var result = ""
        var cursor = plainText.startIndex

        for boundary in boundaries {
            let boundaryIndex = String.Index(utf16Offset: boundary.offset, in: plainText)
            if boundaryIndex > cursor {
                result += plainText[cursor..<boundaryIndex]
                cursor = boundaryIndex
            }
            result += boundary.text
        }
        if cursor < plainText.endIndex {
            result += plainText[cursor...]
        }

        return result
    }

    /// One delimiter insertion point: `text` (an opening or closing
    /// delimiter) gets spliced into `plainText` at `offset` with no
    /// characters consumed.
    private struct Boundary {
        let offset: Int
        let isOpen: Bool
        /// Nesting tie-breaker for boundaries sharing the same `offset`:
        /// on open, larger spans (outer marks) sort first so they wrap
        /// smaller ones; on close, smaller spans (inner marks) sort first
        /// so they close before their enclosing mark does. `TextDecomposition`
        /// never actually emits overlapping/nested marks today (its doc
        /// comment: "only looks at span.marks's first entry"), but this
        /// keeps nesting correct in case that changes.
        let spanLength: Int
        let text: String
    }

    /// Builds and orders every mark's open/close `Boundary`, dropping any
    /// mark whose offsets don't fall within `plainText` (defensive against
    /// stale/malformed `TextMark` rows rather than crashing or corrupting
    /// the export).
    private static func boundaries(for marks: [TextMark], utf16Count: Int) -> [Boundary] {
        var boundaries: [Boundary] = []
        for mark in marks {
            guard mark.startOffset >= 0, mark.endOffset <= utf16Count, mark.startOffset < mark.endOffset else {
                continue
            }
            let (open, close) = delimiters(for: mark)
            guard !open.isEmpty || !close.isEmpty else { continue }

            let length = mark.endOffset - mark.startOffset
            boundaries.append(Boundary(offset: mark.startOffset, isOpen: true, spanLength: length, text: open))
            boundaries.append(Boundary(offset: mark.endOffset, isOpen: false, spanLength: length, text: close))
        }

        return boundaries.sorted { lhs, rhs in
            if lhs.offset != rhs.offset { return lhs.offset < rhs.offset }
            // At the same offset: closes before opens, so two adjacent,
            // non-overlapping marks (e.g. "**a** **b**") stay separate
            // instead of merging into "**a**b**" order. Among boundaries
            // going the same direction, order by `spanLength` per this
            // struct's nesting tie-breaker doc comment.
            if lhs.isOpen != rhs.isOpen { return !lhs.isOpen }
            return lhs.isOpen ? lhs.spanLength > rhs.spanLength : lhs.spanLength < rhs.spanLength
        }
    }

    /// The Markdown delimiter pair for one `TextMark`, matching
    /// `RichTextMark`'s raw values (`BlockContent.swift`) and
    /// `TextDecomposition.strip(_:)`'s reverse mapping. A `link` mark wraps
    /// its range in `[` … `](url)` using `valueText` as the URL; falls back
    /// to no wrapping (both empty) for an unrecognized `markType` so this
    /// never invents delimiters for formatting this build doesn't know
    /// about.
    private static func delimiters(for mark: TextMark) -> (open: String, close: String) {
        switch mark.markType {
        case RichTextMark.bold.rawValue: return ("**", "**")
        case RichTextMark.italic.rawValue: return ("*", "*")
        case RichTextMark.strike.rawValue: return ("~~", "~~")
        case RichTextMark.inlineCode.rawValue: return ("`", "`")
        case RichTextMark.link.rawValue: return ("[", "](\(mark.valueText ?? ""))")
        default: return ("", "")
        }
    }
}
