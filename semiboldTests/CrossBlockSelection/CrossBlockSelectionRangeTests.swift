import Testing
import Foundation

@testable import semibold

/// Pure-logic tests for `BlockOrder`/`CrossBlockSelectionRange` — the part
/// of the cross-block selection mechanism (`01-cross-block-selection-core`
/// brief, A2/A3) that decides, given an anchor/current `DocumentTextLocation`
/// pair and the document's block order, which blocks are "전체 선택 블록"
/// vs "경계 블록" (`CrossBlockSelection/README.md`'s terms) and what each
/// one's own selected character range is. No `UIKit`/gesture/touch
/// involvement at all — this is exactly the kind of logic the brief asked
/// to scope tests toward, given this repo's unit-test-only target.
@MainActor
struct CrossBlockSelectionRangeTests {
    // MARK: - BlockOrder

    @Test("BlockOrder.index(of:) finds a known block's position, and nil for one not in the list")
    func blockOrderIndexOf() {
        let order = BlockOrder(blockIds: ["a", "b", "c"])

        #expect(order.index(of: "a") == 0)
        #expect(order.index(of: "c") == 2)
        #expect(order.index(of: "missing") == nil)
    }

    @Test("BlockOrder.isOrdered(_:atOrBefore:) compares by block position first, offset only within the same block")
    func blockOrderIsOrderedComparesBlockPositionFirst() {
        let order = BlockOrder(blockIds: ["a", "b", "c"])

        // A later block always comes after an earlier block, regardless of
        // character offset within each.
        #expect(order.isOrdered(DocumentTextLocation(blockId: "a", offset: 99), atOrBefore: DocumentTextLocation(blockId: "b", offset: 0)) == true)
        #expect(order.isOrdered(DocumentTextLocation(blockId: "c", offset: 0), atOrBefore: DocumentTextLocation(blockId: "a", offset: 99)) == false)

        // Same block — offset decides.
        #expect(order.isOrdered(DocumentTextLocation(blockId: "a", offset: 2), atOrBefore: DocumentTextLocation(blockId: "a", offset: 5)) == true)
        #expect(order.isOrdered(DocumentTextLocation(blockId: "a", offset: 5), atOrBefore: DocumentTextLocation(blockId: "a", offset: 2)) == false)
        // Equal locations: "at or before" is true.
        #expect(order.isOrdered(DocumentTextLocation(blockId: "a", offset: 5), atOrBefore: DocumentTextLocation(blockId: "a", offset: 5)) == true)
    }

    @Test("BlockOrder.isOrdered(_:atOrBefore:) is nil if either location's block isn't in the order")
    func blockOrderIsOrderedNilForUnknownBlock() {
        let order = BlockOrder(blockIds: ["a", "b"])

        #expect(order.isOrdered(DocumentTextLocation(blockId: "a", offset: 0), atOrBefore: DocumentTextLocation(blockId: "deleted", offset: 0)) == nil)
    }

    // MARK: - CrossBlockSelectionRange.make — normalization (A2/A3's groundwork, touches on A4)

    @Test("make(anchor:current:order:) keeps anchor as start when dragging forward (A2 same-block, A3 crossing blocks)")
    func makeKeepsAnchorAsStartWhenDraggingForward() throws {
        let order = BlockOrder(blockIds: ["a", "b", "c"])
        let anchor = DocumentTextLocation(blockId: "a", offset: 2)
        let current = DocumentTextLocation(blockId: "c", offset: 4)

        let range = try #require(CrossBlockSelectionRange.make(anchor: anchor, current: current, order: order))

        #expect(range.start == anchor)
        #expect(range.end == current)
    }

    @Test("make(anchor:current:order:) swaps current to start when the drag moves before the anchor")
    func makeSwapsWhenCurrentIsBeforeAnchor() throws {
        let order = BlockOrder(blockIds: ["a", "b", "c"])
        let anchor = DocumentTextLocation(blockId: "c", offset: 4)
        let current = DocumentTextLocation(blockId: "a", offset: 2)

        let range = try #require(CrossBlockSelectionRange.make(anchor: anchor, current: current, order: order))

        #expect(range.start == current)
        #expect(range.end == anchor)
    }

    @Test("make(anchor:current:order:) normalizes a backward drag within the same block the same way")
    func makeNormalizesBackwardDragWithinSameBlock() throws {
        let order = BlockOrder(blockIds: ["a"])
        let anchor = DocumentTextLocation(blockId: "a", offset: 8)
        let current = DocumentTextLocation(blockId: "a", offset: 3)

        let range = try #require(CrossBlockSelectionRange.make(anchor: anchor, current: current, order: order))

        #expect(range.start.offset == 3)
        #expect(range.end.offset == 8)
    }

    // MARK: - A4 (시작점보다 문서상 앞으로 드래그 → 자동 정규화) — dedicated coverage

    @Test("A4: dragging from the anchor's block backward into an earlier block normalizes start/end by document order, not drag direction")
    func a4NormalizesWhenCurrentMovesToAnEarlierBlock() throws {
        let order = BlockOrder(blockIds: ["block1", "block2", "block3"])
        // Anchor sits in the *later* block (block2); the drag then moves
        // backward (toward the document start) into block1 — an entirely
        // earlier block, not just "the other end of the same pair" already
        // covered by `makeSwapsWhenCurrentIsBeforeAnchor` above.
        let anchor = DocumentTextLocation(blockId: "block2", offset: 5)
        let current = DocumentTextLocation(blockId: "block1", offset: 2)

        let range = try #require(CrossBlockSelectionRange.make(anchor: anchor, current: current, order: order))

        #expect(range.start == DocumentTextLocation(blockId: "block1", offset: 2))
        #expect(range.end == DocumentTextLocation(blockId: "block2", offset: 5))
    }

    @Test("make(anchor:current:order:) returns nil if either location's block fell out of the order")
    func makeReturnsNilForUnknownBlock() {
        let order = BlockOrder(blockIds: ["a", "b"])
        let anchor = DocumentTextLocation(blockId: "a", offset: 0)
        let current = DocumentTextLocation(blockId: "deleted", offset: 0)

        #expect(CrossBlockSelectionRange.make(anchor: anchor, current: current, order: order) == nil)
    }

    // MARK: - Fully selected vs. boundary blocks

    @Test("A block strictly between start/end's blocks is fully selected")
    func middleBlockIsFullySelected() {
        let order = BlockOrder(blockIds: ["a", "b", "c"])
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: "a", offset: 2),
            end: DocumentTextLocation(blockId: "c", offset: 4)
        )

        #expect(range.isFullySelected(blockId: "b", order: order) == true)
        #expect(range.isBoundary(blockId: "b") == false)
    }

    @Test("start/end blocks are boundary blocks, never fully selected, even if the range spans their whole text")
    func startAndEndBlocksAreAlwaysBoundary() {
        let order = BlockOrder(blockIds: ["a", "b", "c"])
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: "a", offset: 0),
            end: DocumentTextLocation(blockId: "c", offset: 100)
        )

        #expect(range.isBoundary(blockId: "a") == true)
        #expect(range.isFullySelected(blockId: "a", order: order) == false)
        #expect(range.isBoundary(blockId: "c") == true)
        #expect(range.isFullySelected(blockId: "c", order: order) == false)
    }

    @Test("A block outside start/end is neither fully selected nor a boundary block")
    func blockOutsideRangeIsNeither() {
        let order = BlockOrder(blockIds: ["a", "b", "c", "d"])
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: "b", offset: 0),
            end: DocumentTextLocation(blockId: "c", offset: 1)
        )

        #expect(range.isFullySelected(blockId: "a", order: order) == false)
        #expect(range.isBoundary(blockId: "a") == false)
        #expect(range.isFullySelected(blockId: "d", order: order) == false)
        #expect(range.isBoundary(blockId: "d") == false)
    }

    // MARK: - selectedRange(blockId:textLength:order:) — A2 (single-block) scenario

    @Test("A2: a selection that never left its starting block returns that block's own sub-range")
    func sameBlockSelectionReturnsSubRange() throws {
        let order = BlockOrder(blockIds: ["a"])
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: "a", offset: 2),
            end: DocumentTextLocation(blockId: "a", offset: 7)
        )

        let selected = try #require(range.selectedRange(blockId: "a", textLength: 11, order: order))

        #expect(selected == NSRange(location: 2, length: 5))
    }

    // MARK: - selectedRange(blockId:textLength:order:) — A3 (cross-block) scenario

    @Test("A3: the start block's selected range runs from its start offset to the end of its text")
    func startBlockSelectedRangeRunsToEndOfText() throws {
        let order = BlockOrder(blockIds: ["a", "b", "c"])
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: "a", offset: 6),
            end: DocumentTextLocation(blockId: "c", offset: 4)
        )

        let selected = try #require(range.selectedRange(blockId: "a", textLength: 11, order: order))

        #expect(selected == NSRange(location: 6, length: 5))
    }

    @Test("A3: a fully-covered middle block's selected range is its entire text")
    func middleBlockSelectedRangeIsWholeText() throws {
        let order = BlockOrder(blockIds: ["a", "b", "c"])
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: "a", offset: 6),
            end: DocumentTextLocation(blockId: "c", offset: 4)
        )

        let selected = try #require(range.selectedRange(blockId: "b", textLength: 9, order: order))

        #expect(selected == NSRange(location: 0, length: 9))
    }

    @Test("A3: the end block's selected range runs from the start of its text to its end offset")
    func endBlockSelectedRangeRunsFromStartOfText() throws {
        let order = BlockOrder(blockIds: ["a", "b", "c"])
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: "a", offset: 6),
            end: DocumentTextLocation(blockId: "c", offset: 4)
        )

        let selected = try #require(range.selectedRange(blockId: "c", textLength: 8, order: order))

        #expect(selected == NSRange(location: 0, length: 4))
    }

    @Test("A block not touched by the selection at all returns nil, not an empty range")
    func untouchedBlockReturnsNil() {
        let order = BlockOrder(blockIds: ["a", "b", "c", "d"])
        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: "a", offset: 0),
            end: DocumentTextLocation(blockId: "b", offset: 1)
        )

        #expect(range.selectedRange(blockId: "d", textLength: 10, order: order) == nil)
    }

    @Test("A collapsed selection (anchor == current, no drag movement yet) reports isCollapsed")
    func collapsedSelectionReportsIsCollapsed() {
        let location = DocumentTextLocation(blockId: "a", offset: 3)
        let range = CrossBlockSelectionRange(start: location, end: location)

        #expect(range.isCollapsed == true)
    }
}
