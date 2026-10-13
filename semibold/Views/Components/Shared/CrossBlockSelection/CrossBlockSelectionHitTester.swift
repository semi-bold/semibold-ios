import UIKit

/// Converts a raw touch point — in some shared coordinate space, in
/// practice `CrossBlockSelectionOverlay`'s own host view — into a
/// `DocumentTextLocation`, by finding which block's `UITextView` the point
/// falls nearest to and asking that text view's own `closestPosition(to:)`
/// for the exact character offset.
///
/// This is the mechanism `tasks/NO-010.md` §4 asked to be spiked before
/// building the rest of this brief on top of it — see
/// `CrossBlockSelectionHitTesterTests` for what that spike confirmed:
/// `closestPosition(to:)` only needs a point already converted into the
/// *text view's own* coordinate space (via plain `UIView.convert(_:to:)`
/// across the shared block-list view hierarchy — no window membership
/// required), and round-trips back to the exact offset a known
/// `UITextPosition` came from.
///
/// Takes its candidate text views as a plain `[(blockId, UITextView)]`
/// argument rather than reading `BlockTextViewRegistry.shared` directly,
/// so tests can supply a small, self-contained view hierarchy instead of
/// depending on real `ParagraphTextField` rows being mounted.
///
/// **A caveat the spike also surfaced** (`CrossBlockSelectionDragTests
/// .makeTwoBlockFixture`'s doc comment has the concrete repro):
/// `closestPosition(to:)` can resolve incorrectly against a `UITextView`
/// whose `textContainer` hasn't completed a layout pass yet (e.g. right
/// after it's first added to a view hierarchy, before `layoutIfNeeded()`
/// runs). In this app, a block's `UITextView` has always rendered visible
/// text on screen by the time a user could plausibly drag onto it, so this
/// shouldn't bite normal use — but it's worth keeping in mind for A5
/// (auto-scroll mounting a new row *during* an active drag): a row that
/// just became visible mid-scroll might not have finished its first layout
/// pass yet when a touch point first lands on it.

enum CrossBlockSelectionHitTester {
    /// `point` is in `coordinateSpace`'s own coordinates. Returns `nil`
    /// only if `candidates` is empty or `closestPosition(to:)` itself
    /// returns `nil` (UIKit's documented failure case, e.g. an empty text
    /// container) for the chosen block.
    static func location(
        forPoint point: CGPoint,
        in coordinateSpace: UIView,
        candidates: [(blockId: String, textView: UITextView)]
    ) -> DocumentTextLocation? {
        guard !candidates.isEmpty else { return nil }

        // Every candidate's frame, converted into `coordinateSpace` once,
        // so the distance comparisons below all happen in the same space.
        let framedCandidates = candidates.map { candidate in
            (
                blockId: candidate.blockId,
                textView: candidate.textView,
                frame: candidate.textView.convert(candidate.textView.bounds, to: coordinateSpace)
            )
        }

        // Prefer a block whose frame actually contains `point` vertically.
        // Horizontal position never excludes a block on its own — a touch
        // past a short line's last character should still land in that
        // line, not fall through to whatever block happens to be below it.
        let containingBlock = framedCandidates.first { point.y >= $0.frame.minY && point.y <= $0.frame.maxY }
        // Falling in the gap between two blocks, or past the first/last
        // block's edge (e.g. dragging above the very first block, or below
        // the last one currently mounted) resolves to whichever mounted
        // block is vertically nearest.
        let chosenBlock = containingBlock ?? framedCandidates.min(by: {
            verticalDistance(from: point, to: $0.frame) < verticalDistance(from: point, to: $1.frame)
        })
        guard let chosenBlock else { return nil }

        let localPoint = coordinateSpace.convert(point, to: chosenBlock.textView)
        let clampedPoint = CGPoint(
            x: min(max(localPoint.x, 0), max(chosenBlock.textView.bounds.width, 0)),
            y: min(max(localPoint.y, 0), max(chosenBlock.textView.bounds.height, 0))
        )

        guard let position = chosenBlock.textView.closestPosition(to: clampedPoint) else { return nil }
        let offset = chosenBlock.textView.offset(from: chosenBlock.textView.beginningOfDocument, to: position)
        return DocumentTextLocation(blockId: chosenBlock.blockId, offset: offset)
    }

    private static func verticalDistance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        if point.y < frame.minY { return frame.minY - point.y }
        if point.y > frame.maxY { return point.y - frame.maxY }
        return 0
    }
}
