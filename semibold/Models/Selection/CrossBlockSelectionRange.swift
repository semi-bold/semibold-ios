import Foundation

/// A selection's extent, already normalized to document order — `start`
/// always comes at or before `end` in `CrossBlockSelection/README.md`'s
/// sense ("common invariant 1"), regardless of which direction the user
/// actually dragged.
///
/// This type's own `make(anchor:current:order:)` already orders its two
/// inputs by document position every time it's called, which happens to
/// cover the *basic* re-ordering A4 describes ("시작점보다 위로 드래그해도
/// … 재배정된다") as a natural side effect of always computing `start`/
/// `end` fresh from the live anchor/current pair, rather than trying to
/// mutate a previously-fixed `start`/`end` in place. This brief doesn't
/// treat A4 as done, though — only A2/A3 are in scope here
/// (`.claude/features/01-cross-block-selection-core.md`), and A4's own
/// acceptance criterion may call for more than this (e.g. confirming
/// behavior around drag direction reversing mid-gesture, or handle-drag
/// adjustment after the fact) — its implementer should verify this
/// ordering already satisfies what A4 needs rather than assuming it does.
struct CrossBlockSelectionRange: Equatable {
    let start: DocumentTextLocation
    let end: DocumentTextLocation

    /// Orders `anchor`/`current` by document position (per `order`) into a
    /// normalized `start`/`end` pair. `nil` if either location's block
    /// fell out of `order` (e.g. deleted mid-drag).
    static func make(
        anchor: DocumentTextLocation,
        current: DocumentTextLocation,
        order: BlockOrder
    ) -> CrossBlockSelectionRange? {
        guard let anchorAtOrBeforeCurrent = order.isOrdered(anchor, atOrBefore: current) else { return nil }
        return anchorAtOrBeforeCurrent
            ? CrossBlockSelectionRange(start: anchor, end: current)
            : CrossBlockSelectionRange(start: current, end: anchor)
    }

    var isCollapsed: Bool { start == end }

    /// Whether `blockId` sits strictly between `start`/`end`'s blocks —
    /// its entire text is inside the selection, matching
    /// `CrossBlockSelection/README.md`'s "전체 선택 블록" ("선택 범위에
    /// 완전히 포함되어 … 선택 대상인 블록"). `false` for `start.blockId`/
    /// `end.blockId` themselves, even when the selection happens to span
    /// their whole text — the README's definition reserves "전체 선택
    /// 블록" for blocks that aren't a boundary block at all.
    func isFullySelected(blockId: String, order: BlockOrder) -> Bool {
        guard
            let blockIndex = order.index(of: blockId),
            let startIndex = order.index(of: start.blockId),
            let endIndex = order.index(of: end.blockId)
        else { return false }
        return blockIndex > startIndex && blockIndex < endIndex
    }

    /// Whether `blockId` is `start.blockId` or `end.blockId` — only part
    /// of its text is selected, matching the README's "경계 블록".
    func isBoundary(blockId: String) -> Bool {
        blockId == start.blockId || blockId == end.blockId
    }

    /// The selected character range within `blockId`'s own text (UTF-16
    /// offsets, matching `NSRange` conventions), or `nil` if `blockId`
    /// isn't part of this selection at all. `textLength` is that block's
    /// current plain-text length — needed to resolve a fully selected
    /// block's "the whole thing" into a concrete range, and to clamp a
    /// boundary block's range if its text changed since `start`/`end`
    /// were captured.
    func selectedRange(blockId: String, textLength: Int, order: BlockOrder) -> NSRange? {
        let clampedLength = max(0, textLength)
        if isFullySelected(blockId: blockId, order: order) {
            return NSRange(location: 0, length: clampedLength)
        }
        guard isBoundary(blockId: blockId) else { return nil }

        if start.blockId == end.blockId {
            // A single-block selection — both ends sit in this one block.
            let lower = min(start.offset, end.offset).clamped(to: 0...clampedLength)
            let upper = max(start.offset, end.offset).clamped(to: 0...clampedLength)
            return NSRange(location: lower, length: upper - lower)
        }
        if blockId == start.blockId {
            let location = start.offset.clamped(to: 0...clampedLength)
            return NSRange(location: location, length: clampedLength - location)
        }
        // blockId == end.blockId
        let length = end.offset.clamped(to: 0...clampedLength)
        return NSRange(location: 0, length: length)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        // Qualified with `Swift.` — unqualified `min`/`max` inside an
        // `Int` extension resolve to the `Int.min`/`Int.max` static
        // properties (shadowing the global functions of the same name),
        // not the free `min(_:_:)`/`max(_:_:)` this needs.
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
