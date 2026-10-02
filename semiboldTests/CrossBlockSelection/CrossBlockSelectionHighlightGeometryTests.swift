import Testing
import UIKit

@testable import semibold

/// Tests for `CrossBlockSelectionHighlightGeometry` — turning a
/// `CrossBlockSelectionRange` into the actual rects
/// `CrossBlockSelectionOverlay` draws, confirming `CrossBlockSelection
/// /README.md` common invariants 3/4 hold at the geometry layer: a fully
/// selected block's highlight covers its whole text, and a boundary
/// block's highlight only covers its selected sub-range, while every
/// block keeps its own real `UITextView` layout (so highlights follow
/// actual line wrapping, not a guessed-at rect).
@MainActor
struct CrossBlockSelectionHighlightGeometryTests {
    /// Three real, narrow `UITextView`s stacked vertically — "narrow"
    /// so the middle block's text is forced to wrap across more than one
    /// line, which is what actually exercises `selectionRects(for:)`
    /// returning more than one rect for a "fully selected" block.
    private func makeThreeBlockFixture() -> (
        container: UIView, ids: [String], textViews: [String: UITextView]
    ) {
        let ids = ["a-\(UUID().uuidString)", "b-\(UUID().uuidString)", "c-\(UUID().uuidString)"]
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 600))

        let textA = UITextView(frame: CGRect(x: 0, y: 0, width: 120, height: 40))
        textA.text = "Hello world"

        let textB = UITextView(frame: CGRect(x: 0, y: 50, width: 120, height: 80))
        textB.text = "A longer middle block that wraps across two lines"

        let textC = UITextView(frame: CGRect(x: 0, y: 140, width: 120, height: 40))
        textC.text = "Last block text"

        for textView in [textA, textB, textC] {
            textView.font = UIFont.systemFont(ofSize: 16)
            textView.isScrollEnabled = false
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            container.addSubview(textView)
        }
        container.layoutIfNeeded()
        // Forces each text view's own TextKit layout pass, not just the
        // container's — see `CrossBlockSelectionDragTests
        // .makeTwoBlockFixture`'s matching comment for why this matters.
        [textA, textB, textC].forEach { $0.layoutIfNeeded() }

        return (container, ids, [ids[0]: textA, ids[1]: textB, ids[2]: textC])
    }

    @Test("A fully selected middle block highlights its entire text, as multiple rects if it wraps across lines")
    func fullySelectedBlockHighlightsEntireWrappedText() throws {
        let fixture = makeThreeBlockFixture()
        let candidates = fixture.ids.map { (blockId: $0, textView: fixture.textViews[$0]!) }
        let order = BlockOrder(blockIds: fixture.ids)
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: fixture.ids[0], offset: 6),
            end: DocumentTextLocation(blockId: fixture.ids[2], offset: 4)
        )

        let highlights = CrossBlockSelectionHighlightGeometry.highlights(
            for: range, order: order, candidates: candidates, in: fixture.container
        )

        let middleHighlight = try #require(highlights.first { $0.blockId == fixture.ids[1] })
        // The middle block's text is long enough at this width to wrap
        // onto at least 2 lines — `selectionRects(for:)` should report one
        // rect per wrapped line for the full-text selection.
        #expect(middleHighlight.rects.count >= 2)
    }

    @Test("A boundary block's highlight only covers its selected sub-range, not its whole text")
    func boundaryBlockHighlightsOnlySubRange() throws {
        let fixture = makeThreeBlockFixture()
        let candidates = fixture.ids.map { (blockId: $0, textView: fixture.textViews[$0]!) }
        let order = BlockOrder(blockIds: fixture.ids)
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: fixture.ids[0], offset: 6),
            end: DocumentTextLocation(blockId: fixture.ids[2], offset: 4)
        )

        let highlights = CrossBlockSelectionHighlightGeometry.highlights(
            for: range, order: order, candidates: candidates, in: fixture.container
        )

        let startHighlight = try #require(highlights.first { $0.blockId == fixture.ids[0] })
        let fullTextView = fixture.textViews[fixture.ids[0]]!
        let fullTextRange = fullTextView.textRange(
            from: fullTextView.beginningOfDocument, to: fullTextView.endOfDocument
        )!
        let fullWidthRects = fullTextView.selectionRects(for: fullTextRange).map {
            fullTextView.convert($0.rect, to: fixture.container)
        }

        // The boundary block's highlight rect(s) should be narrower than
        // (not equal to) what selecting its entire text would produce —
        // confirms this isn't accidentally treating a boundary block as
        // "fully selected".
        let startHighlightWidth = startHighlight.rects.reduce(0) { $0 + $1.width }
        let fullWidth = fullWidthRects.reduce(0) { $0 + $1.width }
        #expect(startHighlightWidth < fullWidth)
    }

    @Test("A block outside the selection produces no highlight at all")
    func blockOutsideSelectionProducesNoHighlight() {
        let fixture = makeThreeBlockFixture()
        let candidates = fixture.ids.map { (blockId: $0, textView: fixture.textViews[$0]!) }
        let order = BlockOrder(blockIds: fixture.ids)
        // Selection only spans the first two blocks.
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: fixture.ids[0], offset: 0),
            end: DocumentTextLocation(blockId: fixture.ids[1], offset: 1)
        )

        let highlights = CrossBlockSelectionHighlightGeometry.highlights(
            for: range, order: order, candidates: candidates, in: fixture.container
        )

        #expect(highlights.contains { $0.blockId == fixture.ids[2] } == false)
    }

    @Test("A collapsed selection (no drag movement yet) produces no highlights")
    func collapsedSelectionProducesNoHighlights() {
        let fixture = makeThreeBlockFixture()
        let candidates = fixture.ids.map { (blockId: $0, textView: fixture.textViews[$0]!) }
        let order = BlockOrder(blockIds: fixture.ids)
        let location = DocumentTextLocation(blockId: fixture.ids[0], offset: 3)
        let range = CrossBlockSelectionRange(start: location, end: location)

        let highlights = CrossBlockSelectionHighlightGeometry.highlights(
            for: range, order: order, candidates: candidates, in: fixture.container
        )

        #expect(highlights.isEmpty)
    }
}
