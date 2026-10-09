import Foundation

/// Turns a cross-block (or single-block) selection range into the two
/// clipboard representations `tasks/NO-010.md` §3.1 ("클립보드 이중 표현")
/// calls for — this app's own lossless `BlockClipboardPayload` and a
/// Markdown fallback string — without touching `UIPasteboard` or Core Data
/// itself.
///
/// Kept as a pure function over already-loaded, in-memory model data
/// (`DetailViewModel.items`/`.textContents`/`.marksByItemId`, plus whatever
/// `ListGroup` rows the selected items reference) so it's directly
/// unit-testable with no view-model/pasteboard/database setup at all
/// (`03-copy-action` brief's AC1 parenthetical — "메뉴 UI 없이 직접 호출하는
/// 유닛 테스트로 검증"). `DetailViewModel+CrossBlockSelectionActions.swift`
/// is the only caller that resolves real model data and writes the result
/// to a pasteboard.
///
/// Every item `range` touches at all — "전체 선택 블록" and "경계 블록"
/// alike (`CrossBlockSelection/README.md`) — is handled by the exact same
/// code path below: `CrossBlockSelectionRange.selectedRange(blockId:
/// textLength:order:)` already returns a fully selected block's whole-text
/// range the same way it returns a boundary block's partial one, so
/// slicing `plainText`/`TextMark`s to that one range reproduces the
/// original text verbatim for a fully selected block (common invariant 3)
/// and only the selected substring for a boundary block (common invariant
/// 4) — no branching between the two cases is needed here.
enum CrossBlockSelectionClipboardSerializer {
    /// Both clipboard representations for one selection range, ready for a
    /// caller to write to `UIPasteboard` — or, in this brief's unit tests,
    /// to assert on directly without touching a pasteboard at all.
    struct Result {
        let payload: BlockClipboardPayload
        let markdown: String
    }

    /// - Parameters:
    ///   - range: The selection to serialize, already normalized
    ///     (`CrossBlockSelectionRange.make`).
    ///   - order: The document's block order `range` was computed against.
    ///   - documentTitle: Passed straight through to `MarkdownExporter`
    ///     (currently unused by it, kept for forward compatibility — see
    ///     its own doc comment).
    ///   - items: The document's items in display order
    ///     (`DetailViewModel.items`).
    ///   - textContentsByItemId: Each item's text detail, keyed by item
    ///     id. An item with no entry here (e.g. a future non-text content
    ///     type `MarkdownExporter` itself also skips) is left out of the
    ///     result — there's no text to slice a selected range out of.
    ///   - marksByItemId: Each item's inline formatting marks, keyed by
    ///     item id. Missing/empty for an item with none.
    ///   - listGroupsById: The `ListGroup` rows referenced by any selected
    ///     list item's `listGroupId`, keyed by that id — callers resolve
    ///     these from `ListGroupRepository` before calling in, since this
    ///     function itself never touches Core Data. Serialized verbatim,
    ///     same id and all: this step never reassigns or merges a
    ///     `listGroupId`, even for a selection that only covers part of a
    ///     group's members (B2) — that reassignment is paste's job
    ///     (`tasks/NO-010.md` §3.2), not copy's.
    static func serialize(
        range: CrossBlockSelectionRange,
        order: BlockOrder,
        documentTitle: String,
        items: [DocumentItem],
        textContentsByItemId: [String: TextContent],
        marksByItemId: [String: [TextMark]],
        listGroupsById: [String: ListGroup]
    ) -> Result {
        var selectedItems: [DocumentItem] = []
        var selectedTextContents: [TextContent] = []
        var selectedMarks: [TextMark] = []
        var referencedListGroupIds: Set<String> = []
        var textContentsForMarkdown: [String: TextContent] = [:]
        var marksForMarkdown: [String: [TextMark]] = [:]

        for item in items {
            guard let content = textContentsByItemId[item.id] else { continue }
            guard let selected = range.selectedRange(
                blockId: item.id,
                textLength: content.plainText.utf16.count,
                order: order
            ) else { continue }

            var slicedContent = content
            slicedContent.plainText = Self.substring(of: content.plainText, in: selected)

            let slicedMarks = Self.clip(marksByItemId[item.id] ?? [], to: selected)

            selectedItems.append(item)
            selectedTextContents.append(slicedContent)
            selectedMarks.append(contentsOf: slicedMarks)
            textContentsForMarkdown[item.id] = slicedContent
            marksForMarkdown[item.id] = slicedMarks

            if let listGroupId = item.listGroupId {
                referencedListGroupIds.insert(listGroupId)
            }
        }

        let selectedListGroups = referencedListGroupIds.compactMap { listGroupsById[$0] }

        let payload = BlockClipboardPayload(
            items: selectedItems,
            textContents: selectedTextContents,
            listGroups: selectedListGroups,
            textMarks: selectedMarks
        )
        let markdown = MarkdownExporter.render(
            documentTitle: documentTitle,
            items: selectedItems,
            textContents: textContentsForMarkdown,
            marksByItemId: marksForMarkdown
        )

        return Result(payload: payload, markdown: markdown)
    }

    /// `text`'s substring at `nsRange` (UTF-16 offsets). Falls back to
    /// `text` unchanged if the range can't be resolved against it — should
    /// only happen if `nsRange` was computed against a stale text length;
    /// `CrossBlockSelectionRange.selectedRange` already clamps to the
    /// text's current length, so this is a defensive fallback, not an
    /// expected path.
    private static func substring(of text: String, in nsRange: NSRange) -> String {
        guard let range = Range(nsRange, in: text) else { return text }
        return String(text[range])
    }

    /// Keeps only the marks (or the overlapping slice of a mark) that fall
    /// within `nsRange`, with offsets shifted to be relative to the start
    /// of that range — matching how `substring(of:in:)` re-bases the
    /// sliced text to start at 0. A mark entirely outside `nsRange` is
    /// dropped; one that only partially overlaps is clipped to the part
    /// that's actually included, same as the text itself.
    private static func clip(_ marks: [TextMark], to nsRange: NSRange) -> [TextMark] {
        let lowerBound = nsRange.location
        let upperBound = nsRange.location + nsRange.length
        return marks.compactMap { mark -> TextMark? in
            let clippedStart = max(mark.startOffset, lowerBound)
            let clippedEnd = min(mark.endOffset, upperBound)
            guard clippedStart < clippedEnd else { return nil }
            var clipped = mark
            clipped.startOffset = clippedStart - lowerBound
            clipped.endOffset = clippedEnd - lowerBound
            return clipped
        }
    }
}
