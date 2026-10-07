import UIKit

/// One block's highlight within a cross-block selection — either the
/// whole block (a fully selected block's whole text, per
/// `CrossBlockSelection/README.md`'s "전체 선택 블록") or sub-rects
/// following the selected characters' actual line-wrapped layout (a
/// boundary block's partial selection), all already converted into
/// `CrossBlockSelectionOverlay`'s own coordinate space so it can draw them
/// directly without any further conversion.
struct BlockSelectionHighlight {
    let blockId: String
    let rects: [CGRect]
}

enum CrossBlockSelectionHighlightGeometry {
    /// Computes every candidate block's highlight rect(s) for `range`, in
    /// `coordinateSpace`. A block outside `range` — or one not currently
    /// mounted at all, since it's simply missing from `candidates`
    /// (`BlockTextViewRegistry`'s doc comment) — just doesn't appear in
    /// the result; this never guesses geometry for a block it can't
    /// directly measure.
    static func highlights(
        for range: CrossBlockSelectionRange,
        order: BlockOrder,
        candidates: [(blockId: String, textView: UITextView)],
        in coordinateSpace: UIView
    ) -> [BlockSelectionHighlight] {
        candidates.compactMap { candidate in
            let textLength = candidate.textView.text?.utf16.count ?? 0
            guard
                let selected = range.selectedRange(blockId: candidate.blockId, textLength: textLength, order: order),
                selected.length > 0
            else { return nil }

            let rects = selectionRects(for: selected, in: candidate.textView, convertedTo: coordinateSpace)
            guard !rects.isEmpty else { return nil }
            return BlockSelectionHighlight(blockId: candidate.blockId, rects: rects)
        }
    }

    /// Converts an `NSRange` into the visual rect(s) `UITextView` itself
    /// would highlight for that range, via `selectionRects(for:)` — this
    /// already accounts for line wrapping, so a boundary block's partial
    /// selection draws one rect per wrapped line instead of one rect that
    /// incorrectly spans the block's full width.
    private static func selectionRects(
        for range: NSRange,
        in textView: UITextView,
        convertedTo coordinateSpace: UIView
    ) -> [CGRect] {
        guard
            let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
            let end = textView.position(from: textView.beginningOfDocument, offset: range.location + range.length),
            let textRange = textView.textRange(from: start, to: end)
        else { return [] }

        return textView.selectionRects(for: textRange).map {
            textView.convert($0.rect, to: coordinateSpace)
        }
    }
}
