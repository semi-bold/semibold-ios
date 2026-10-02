import Testing
import UIKit

@testable import semibold

/// Tests for `CrossBlockSelectionTracker` — the live state A2 ("같은 블록
/// 안에서 드래그해도 커스텀 선택 로직이 동작한다")/A3 ("드래그가 현재
/// 블록의 위/아래 경계를 넘어도 … 같은 커스텀 선택 로직이 이어지며")
/// share, plus end-to-end scenarios wiring the tracker up to real
/// `UITextView`s through `BlockTextViewRegistry`/
/// `CrossBlockSelectionHighlightGeometry` to confirm the whole pipeline
/// (hit-test → tracker state → highlight rects) produces the right answer
/// for the exact "drag starts in one block, crosses into the next" case
/// A3 describes.
///
/// **Why this doesn't simulate an actual finger drag.** Same limitation
/// `CrossBlockSelectionA1RegressionTests` already documents — no XCUITest
/// target, no live window/responder chain to deliver real touch events
/// through. These tests instead drive `CrossBlockSelectionTracker`
/// directly the way `CrossBlockSelectionOverlay.Coordinator.handleLongPress(_:)`
/// would (resolve a point to a location, call `beginSelection`/
/// `extendSelection`), which is exactly the "pure logic" half of the
/// mechanism the brief asked tests to focus on — the gesture-recognizer
/// wiring itself needs manual/device verification
/// (`CrossBlockSelectionOverlay`'s doc comment).
@MainActor
struct CrossBlockSelectionDragTests {
    // MARK: - Tracker state transitions

    @Test("A fresh tracker has no active selection")
    func freshTrackerIsInactive() {
        let tracker = CrossBlockSelectionTracker()

        #expect(tracker.isActive == false)
        #expect(tracker.isDragging == false)
        #expect(tracker.anchor == nil)
        #expect(tracker.current == nil)
    }

    @Test("beginSelection(at:) sets both anchor and current to the same location, and starts dragging")
    func beginSelectionSetsAnchorAndCurrent() {
        let tracker = CrossBlockSelectionTracker()
        let location = DocumentTextLocation(blockId: "a", offset: 3)

        tracker.beginSelection(at: location)

        #expect(tracker.anchor == location)
        #expect(tracker.current == location)
        #expect(tracker.isActive == true)
        #expect(tracker.isDragging == true)
    }

    @Test("A2: extendSelection(to:) within the same block updates current without moving anchor")
    func extendSelectionWithinSameBlock() {
        let tracker = CrossBlockSelectionTracker()
        let anchor = DocumentTextLocation(blockId: "a", offset: 2)
        tracker.beginSelection(at: anchor)

        tracker.extendSelection(to: DocumentTextLocation(blockId: "a", offset: 7))

        #expect(tracker.anchor == anchor)
        #expect(tracker.current == DocumentTextLocation(blockId: "a", offset: 7))
    }

    @Test("A3: extendSelection(to:) into a different block is the exact same call as A2 — no branching for crossing a boundary")
    func extendSelectionAcrossBlockBoundary() {
        let tracker = CrossBlockSelectionTracker()
        let anchor = DocumentTextLocation(blockId: "a", offset: 2)
        tracker.beginSelection(at: anchor)

        // Same method, same call shape, as extendSelectionWithinSameBlock
        // above — just a `DocumentTextLocation` in a different block.
        tracker.extendSelection(to: DocumentTextLocation(blockId: "b", offset: 3))

        #expect(tracker.anchor == anchor)
        #expect(tracker.current == DocumentTextLocation(blockId: "b", offset: 3))
    }

    @Test("extendSelection(to:) before beginSelection is a no-op — the tracker stays inactive")
    func extendSelectionBeforeBeginIsNoOp() {
        let tracker = CrossBlockSelectionTracker()

        tracker.extendSelection(to: DocumentTextLocation(blockId: "a", offset: 1))

        #expect(tracker.isActive == false)
    }

    @Test("endSelection() stops dragging but keeps the selection (anchor/current) around")
    func endSelectionKeepsSelectionVisible() {
        let tracker = CrossBlockSelectionTracker()
        tracker.beginSelection(at: DocumentTextLocation(blockId: "a", offset: 0))
        tracker.extendSelection(to: DocumentTextLocation(blockId: "b", offset: 2))

        tracker.endSelection()

        #expect(tracker.isDragging == false)
        #expect(tracker.isActive == true)
        #expect(tracker.current == DocumentTextLocation(blockId: "b", offset: 2))
    }

    @Test("cancel() clears the selection entirely")
    func cancelClearsSelection() {
        let tracker = CrossBlockSelectionTracker()
        tracker.beginSelection(at: DocumentTextLocation(blockId: "a", offset: 0))
        tracker.extendSelection(to: DocumentTextLocation(blockId: "b", offset: 2))

        tracker.cancel()

        #expect(tracker.isActive == false)
        #expect(tracker.isDragging == false)
        #expect(tracker.anchor == nil)
        #expect(tracker.current == nil)
    }

    @Test("range(order:) returns nil while inactive")
    func rangeIsNilWhileInactive() {
        let tracker = CrossBlockSelectionTracker()
        let order = BlockOrder(blockIds: ["a", "b"])

        #expect(tracker.range(order: order) == nil)
    }

    @Test("range(order:) normalizes anchor/current the same way regardless of drag direction")
    func rangeNormalizesRegardlessOfDirection() throws {
        let tracker = CrossBlockSelectionTracker()
        let order = BlockOrder(blockIds: ["a", "b", "c"])
        // Anchor in "c", dragged backward into "a" — A4's basic ordering,
        // exercised here only as a consequence of A3's same-mechanism
        // requirement, not claimed as A4 itself (see
        // `CrossBlockSelectionRange.make`'s doc comment).
        tracker.beginSelection(at: DocumentTextLocation(blockId: "c", offset: 4))
        tracker.extendSelection(to: DocumentTextLocation(blockId: "a", offset: 1))

        let range = try #require(tracker.range(order: order))

        #expect(range.start == DocumentTextLocation(blockId: "a", offset: 1))
        #expect(range.end == DocumentTextLocation(blockId: "c", offset: 4))
    }

    // MARK: - End-to-end: hit-test → tracker → highlight geometry, across a block boundary (A3)

    /// Builds a small, self-contained "block list" — two real `UITextView`s
    /// stacked vertically in a container, registered under test-unique
    /// block ids — standing in for two mounted `ParagraphTextField` rows.
    /// Unregisters both at the end (via the returned cleanup closure) so
    /// this test's ids never leak into `BlockTextViewRegistry.shared`'s
    /// state for any other test that happens to run in the same process.
    private func makeTwoBlockFixture() -> (
        container: UIView, blockAId: String, blockBId: String, blockA: UITextView, blockB: UITextView, cleanup: () -> Void
    ) {
        let blockAId = "drag-test-a-\(UUID().uuidString)"
        let blockBId = "drag-test-b-\(UUID().uuidString)"
        let width: CGFloat = 300

        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 600))

        // Sized tightly to its own single line of text via `sizeThatFits`
        // — matching how a real `ParagraphTextField` row is actually sized
        // (`ParagraphTextField.sizeThatFits`), with no extra empty space
        // below the text inside the text view's own bounds. A taller,
        // arbitrary frame would leave a dead zone below the rendered line
        // where `closestPosition(to:)` falls back to "end of text"
        // regardless of x — a real (if obscure) UIKit quirk for a point
        // below the last line's bottom edge, not a bug in this brief's own
        // hit-testing code.
        let blockA = makeTightlyFitTextView(text: "Hello world", width: width)
        let blockB = makeTightlyFitTextView(text: "Second block", width: width)
        blockB.frame.origin.y = blockA.frame.maxY

        container.addSubview(blockA)
        container.addSubview(blockB)
        container.layoutIfNeeded()

        BlockTextViewRegistry.shared.register(blockId: blockAId, textView: blockA)
        BlockTextViewRegistry.shared.register(blockId: blockBId, textView: blockB)

        let cleanup = {
            BlockTextViewRegistry.shared.unregister(blockId: blockAId)
            BlockTextViewRegistry.shared.unregister(blockId: blockBId)
        }
        return (container, blockAId, blockBId, blockA, blockB, cleanup)
    }

    /// A `UITextView` configured the same way `ParagraphTextField.makeUIView`
    /// configures every block's text view, sized to exactly fit `text` at
    /// `width` — see `makeTwoBlockFixture`'s doc comment for why tight
    /// sizing matters here.
    private func makeTightlyFitTextView(text: String, width: CGFloat) -> UITextView {
        let textView = UITextView()
        textView.text = text
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        let fittedSize = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        textView.frame = CGRect(x: 0, y: 0, width: width, height: fittedSize.height)
        textView.layoutIfNeeded()
        return textView
    }

    @Test("A3 end-to-end: a drag that starts in one block and ends in the next produces a two-block highlight — a boundary block plus another boundary block, no 'fully selected' middle block needed for just two blocks")
    func dragAcrossBlockBoundaryProducesTwoBlockHighlight() throws {
        let fixture = makeTwoBlockFixture()
        defer { fixture.cleanup() }

        let order = BlockOrder(blockIds: [fixture.blockAId, fixture.blockBId])
        let tracker = CrossBlockSelectionTracker()

        // Anchor: hit-test a point in the middle of block A's text (its
        // frame's vertical center, safely inside its one line of text).
        let anchorLocation = try #require(
            CrossBlockSelectionHitTester.location(
                forPoint: CGPoint(x: 10, y: fixture.blockA.frame.midY),
                in: fixture.container,
                candidates: [(fixture.blockAId, fixture.blockA), (fixture.blockBId, fixture.blockB)]
            )
        )
        #expect(anchorLocation.blockId == fixture.blockAId)
        tracker.beginSelection(at: anchorLocation)

        // Drag continues down past block A's bottom edge, into block B —
        // A3's "경계를 넘는" moment. No special handling is invoked here;
        // this is the exact same `extendSelection` call A2 uses.
        let currentLocation = try #require(
            CrossBlockSelectionHitTester.location(
                forPoint: CGPoint(x: 10, y: fixture.blockB.frame.midY),
                in: fixture.container,
                candidates: [(fixture.blockAId, fixture.blockA), (fixture.blockBId, fixture.blockB)]
            )
        )
        #expect(currentLocation.blockId == fixture.blockBId)
        tracker.extendSelection(to: currentLocation)

        let range = try #require(tracker.range(order: order))
        #expect(range.start.blockId == fixture.blockAId)
        #expect(range.end.blockId == fixture.blockBId)

        let highlights = CrossBlockSelectionHighlightGeometry.highlights(
            for: range,
            order: order,
            candidates: [(fixture.blockAId, fixture.blockA), (fixture.blockBId, fixture.blockB)],
            in: fixture.container
        )

        let highlightedBlockIds = Set(highlights.map(\.blockId))
        #expect(highlightedBlockIds == Set([fixture.blockAId, fixture.blockBId]))
        // Both boundary blocks must have produced at least one real rect
        // to draw — not just a recorded range with nothing to show.
        #expect(highlights.allSatisfy { !$0.rects.isEmpty })
    }

    @Test("A2 end-to-end: a drag that stays within one block produces exactly one block's highlight")
    func dragWithinOneBlockProducesSingleBlockHighlight() throws {
        let fixture = makeTwoBlockFixture()
        defer { fixture.cleanup() }

        let order = BlockOrder(blockIds: [fixture.blockAId, fixture.blockBId])
        let tracker = CrossBlockSelectionTracker()

        let anchorLocation = try #require(
            CrossBlockSelectionHitTester.location(
                forPoint: CGPoint(x: 5, y: fixture.blockA.frame.midY),
                in: fixture.container,
                candidates: [(fixture.blockAId, fixture.blockA), (fixture.blockBId, fixture.blockB)]
            )
        )
        tracker.beginSelection(at: anchorLocation)

        let currentLocation = try #require(
            CrossBlockSelectionHitTester.location(
                forPoint: CGPoint(x: 60, y: fixture.blockA.frame.midY),
                in: fixture.container,
                candidates: [(fixture.blockAId, fixture.blockA), (fixture.blockBId, fixture.blockB)]
            )
        )
        tracker.extendSelection(to: currentLocation)

        let range = try #require(tracker.range(order: order))
        #expect(range.start.blockId == fixture.blockAId)
        #expect(range.end.blockId == fixture.blockAId)

        let highlights = CrossBlockSelectionHighlightGeometry.highlights(
            for: range,
            order: order,
            candidates: [(fixture.blockAId, fixture.blockA), (fixture.blockBId, fixture.blockB)],
            in: fixture.container
        )

        #expect(highlights.map(\.blockId) == [fixture.blockAId])
    }
}
