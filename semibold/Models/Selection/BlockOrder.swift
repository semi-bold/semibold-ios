import Foundation

/// The document's block ids in on-screen reading order — what a
/// cross-block selection range needs to tell which of two
/// `DocumentTextLocation` values comes first, since a character offset
/// alone only orders two locations *within* the same block.
///
/// Built fresh from `DetailViewModel.items.map(\.id)` (already flattened
/// into display order) wherever it's needed, rather than cached anywhere —
/// it's a plain value derived from data the view model already keeps
/// current, so there's no separate copy that could go stale after a block
/// insert/delete/reorder mid-drag.
struct BlockOrder {
    let blockIds: [String]

    /// `nil` if `blockId` isn't part of this order at all — e.g. a block
    /// deleted while a drag that had started inside it is still active.
    func index(of blockId: String) -> Int? {
        blockIds.firstIndex(of: blockId)
    }

    /// Whether `a` comes at or before `b` in document order — compares
    /// block position first, then (only for two locations in the same
    /// block) character offset. `nil` if either location's block isn't
    /// part of this order.
    func isOrdered(_ a: DocumentTextLocation, atOrBefore b: DocumentTextLocation) -> Bool? {
        guard let indexA = index(of: a.blockId), let indexB = index(of: b.blockId) else { return nil }
        if indexA != indexB { return indexA < indexB }
        return a.offset <= b.offset
    }
}
