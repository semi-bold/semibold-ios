import Testing
import UIKit

@testable import semibold

/// Validates `tasks/NO-010.md` §4's required feasibility spike before the
/// rest of this brief (`01-cross-block-selection-core`) was built on top
/// of it: "착수 전 `closestPosition(to:)` 기반 접근이 실제로 동작하는지
/// 작은 스파이크로 먼저 검증한다."
///
/// **What this confirms.** `UITextView.closestPosition(to:)` is a pure
/// text-layout (TextKit) query — it only needs a point already expressed
/// in the text view's own coordinate space, a laid-out `textContainer`,
/// and no window membership or live responder chain at all. Converting a
/// touch point from an arbitrary shared coordinate space (here, a plain
/// container `UIView` standing in for `CrossBlockSelectionOverlay`'s host
/// view) into each candidate block's own space is just
/// `UIView.convert(_:to:)` across the normal view hierarchy — also no
/// window required, since `convert` walks `superview` frame transforms,
/// not window-relative screen coordinates.
///
/// **What this does NOT confirm** (and isn't claimed to) — whether this
/// overlay's `UILongPressGestureRecognizer` actually coexists cleanly with
/// each block's own native long-press/pan recognizers at the moment a
/// long-press turns into a drag, without a visible flash of native
/// selection UI. That's a live-touch/responder-chain question this
/// unit-test-only target can't simulate (`CrossBlockSelectionOverlay`'s
/// doc comment) — flagged for manual/device verification, not silently
/// assumed to work because the math below does.
@MainActor
struct CrossBlockSelectionHitTesterTests {
    /// Builds a `UITextView` configured the same way
    /// `ParagraphTextField.makeUIView` configures every block's text view,
    /// with a fixed width (so wrapping is deterministic) and a forced
    /// layout pass — `closestPosition(to:)`/`caretRect(for:)` both need
    /// `textContainer` to have actually laid out its glyphs at least once.
    private func makeConfiguredTextView(text: String, frame: CGRect) -> UITextView {
        let textView = UITextView(frame: frame)
        textView.text = text
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.layoutIfNeeded()
        return textView
    }

    // MARK: - Spike: closestPosition(to:) round-trips a known offset

    @Test("closestPosition(to:) resolves back to the exact offset a known UITextPosition's caret rect came from, with no window needed")
    func closestPositionRoundTripsKnownOffsets() throws {
        let text = "Hello world"
        let textView = makeConfiguredTextView(text: text, frame: CGRect(x: 0, y: 0, width: 200, height: 40))

        for offset in [0, 1, 5, 6, text.utf16.count] {
            let position = try #require(textView.position(from: textView.beginningOfDocument, offset: offset))
            let caretRect = textView.caretRect(for: position)
            let probePoint = CGPoint(x: caretRect.midX, y: caretRect.midY)

            let resolvedPosition = try #require(textView.closestPosition(to: probePoint))
            let resolvedOffset = textView.offset(from: textView.beginningOfDocument, to: resolvedPosition)

            #expect(resolvedOffset == offset, "offset \(offset) round-tripped to \(resolvedOffset)")
        }
    }

    @Test("closestPosition(to:) clamps an out-of-bounds point to the nearest valid offset instead of returning nil")
    func closestPositionClampsOutOfBoundsPoints() throws {
        let text = "Hello world"
        let textView = makeConfiguredTextView(text: text, frame: CGRect(x: 0, y: 0, width: 200, height: 40))

        let beforeStart = try #require(textView.closestPosition(to: CGPoint(x: -50, y: -50)))
        #expect(textView.offset(from: textView.beginningOfDocument, to: beforeStart) == 0)

        let afterEnd = try #require(textView.closestPosition(to: CGPoint(x: 1000, y: 1000)))
        #expect(textView.offset(from: textView.beginningOfDocument, to: afterEnd) == text.utf16.count)
    }

    // MARK: - Spike: converting a point across the block-list view hierarchy

    @Test("A point in a shared container's coordinate space converts correctly into a specific block's own text-view space, with no window needed")
    func pointConvertsAcrossViewHierarchyWithoutAWindow() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let textView = makeConfiguredTextView(text: "Block text", frame: CGRect(x: 20, y: 100, width: 260, height: 40))
        container.addSubview(textView)

        // A point 10pt into the text view, expressed in the container's
        // coordinate space (as a touch delivered to an overlay sitting
        // above the whole list would be).
        let pointInContainer = CGPoint(x: 30, y: 110)
        let pointInTextView = container.convert(pointInContainer, to: textView)

        #expect(pointInTextView == CGPoint(x: 10, y: 10))
    }

    // MARK: - Multi-block hit testing

    @Test("A point inside a block's own frame resolves to that block")
    func locationResolvesToBlockContainingPoint() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let blockA = makeConfiguredTextView(text: "Block A text", frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        let blockB = makeConfiguredTextView(text: "Block B text", frame: CGRect(x: 0, y: 50, width: 300, height: 40))
        container.addSubview(blockA)
        container.addSubview(blockB)
        let candidates = [(blockId: "A", textView: blockA), (blockId: "B", textView: blockB)]

        let locationInA = CrossBlockSelectionHitTester.location(
            forPoint: CGPoint(x: 10, y: 20), in: container, candidates: candidates
        )
        #expect(locationInA?.blockId == "A")

        let locationInB = CrossBlockSelectionHitTester.location(
            forPoint: CGPoint(x: 10, y: 60), in: container, candidates: candidates
        )
        #expect(locationInB?.blockId == "B")
    }

    @Test("A point in the gap between two blocks resolves to whichever block is vertically nearest")
    func locationInGapResolvesToNearestBlock() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let blockA = makeConfiguredTextView(text: "Block A text", frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        let blockB = makeConfiguredTextView(text: "Block B text", frame: CGRect(x: 0, y: 50, width: 300, height: 40))
        container.addSubview(blockA)
        container.addSubview(blockB)
        let candidates = [(blockId: "A", textView: blockA), (blockId: "B", textView: blockB)]

        // The 10pt gap is y = 40...50 — y=44 is nearer A's bottom edge.
        let nearA = CrossBlockSelectionHitTester.location(
            forPoint: CGPoint(x: 10, y: 44), in: container, candidates: candidates
        )
        #expect(nearA?.blockId == "A")

        // y=47 is nearer B's top edge.
        let nearB = CrossBlockSelectionHitTester.location(
            forPoint: CGPoint(x: 10, y: 47), in: container, candidates: candidates
        )
        #expect(nearB?.blockId == "B")
    }

    @Test("A point above the first block resolves to it; a point below the last mounted block resolves to it")
    func locationBeyondEdgesResolvesToNearestEndBlock() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let blockA = makeConfiguredTextView(text: "Block A text", frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        let blockB = makeConfiguredTextView(text: "Block B text", frame: CGRect(x: 0, y: 50, width: 300, height: 40))
        container.addSubview(blockA)
        container.addSubview(blockB)
        let candidates = [(blockId: "A", textView: blockA), (blockId: "B", textView: blockB)]

        let aboveAll = CrossBlockSelectionHitTester.location(
            forPoint: CGPoint(x: 10, y: -20), in: container, candidates: candidates
        )
        #expect(aboveAll?.blockId == "A")

        let belowAll = CrossBlockSelectionHitTester.location(
            forPoint: CGPoint(x: 10, y: 500), in: container, candidates: candidates
        )
        #expect(belowAll?.blockId == "B")
    }

    @Test("A point past a line's last character still resolves inside that block, not the next one — horizontal position never excludes a containing block")
    func locationPastLineEndStaysInContainingBlock() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let blockA = makeConfiguredTextView(text: "Hi", frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        let blockB = makeConfiguredTextView(text: "Block B text", frame: CGRect(x: 0, y: 50, width: 300, height: 40))
        container.addSubview(blockA)
        container.addSubview(blockB)
        let candidates = [(blockId: "A", textView: blockA), (blockId: "B", textView: blockB)]

        // Far to the right of "Hi"'s short text, but still vertically
        // inside blockA's own frame.
        let location = CrossBlockSelectionHitTester.location(
            forPoint: CGPoint(x: 280, y: 20), in: container, candidates: candidates
        )
        #expect(location?.blockId == "A")
        #expect(location?.offset == 2)
    }

    @Test("No candidates resolves to nil")
    func noCandidatesResolvesToNil() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))

        let location = CrossBlockSelectionHitTester.location(forPoint: CGPoint(x: 10, y: 10), in: container, candidates: [])

        #expect(location == nil)
    }
}
