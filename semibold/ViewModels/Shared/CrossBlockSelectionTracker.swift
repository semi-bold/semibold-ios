import Foundation

/// Live state for one in-progress (or just-finished) cross-block
/// drag-selection — the single mechanism `tasks/NO-010.md` §4's "적용
/// 범위 확장" decision (2026-10-01) uses for every drag-selection, whether
/// it stays inside one block (A2) or crosses into others (A3). There is no
/// separate "native selection" code path this falls back to or hands off
/// to at a block boundary — `extendSelection(to:)` is the same call either
/// way.
///
/// Owned by `DetailScreen` (one instance per open document), driven by
/// `CrossBlockSelectionOverlay`'s gesture recognizer as the user's finger
/// moves, and read by that same overlay to compute what to highlight.
///
/// **Caret placement is untouched and has nothing to do with this type.**
/// Tapping (or a long-press that never turns into a drag) to move the
/// typing cursor stays native `UITextView` behavior
/// (`CrossBlockSelectionA1RegressionTests`) — this tracker only exists to
/// represent the act of dragging out a (possibly still empty) *range*,
/// per this brief's Scope ("타이핑을 위한 캐럿 배치 … 는 이 범위에
/// 포함되지 않는다").
@Observable
@MainActor
final class CrossBlockSelectionTracker {
    /// Where the drag started — set once, the moment a long-press-then-move
    /// first crosses the movement threshold that distinguishes an
    /// intentional drag from a stationary long-press
    /// (`CrossBlockSelectionOverlay.Coordinator.dragThreshold`). Not moved
    /// again until `endSelection()`/`cancel()`.
    private(set) var anchor: DocumentTextLocation?

    /// Where the drag currently is — updated continuously as the finger
    /// moves, including across a block's top/bottom edge (A3), with no
    /// branching at the crossing itself: `extendSelection(to:)` doesn't
    /// know or care whether `location` is in the same block `anchor` is.
    private(set) var current: DocumentTextLocation?

    /// Whether a drag is actively in progress (finger still down) —
    /// becomes `false` once it lifts, even though `anchor`/`current` (and
    /// so the selected range) stay around until `cancel()` is called, the
    /// same way a native text selection's handles stay up after the drag
    /// that created them ends. `CrossBlockSelectionHighlightView` draws
    /// handles whenever `isActive`, not just while `isDragging`.
    private(set) var isDragging = false

    /// Whether a selection currently exists at all (drag in progress, or
    /// just finished and not yet cancelled).
    var isActive: Bool { anchor != nil }

    /// Starts a new selection at `location` — called once per gesture, the
    /// moment the drag threshold is first crossed.
    func beginSelection(at location: DocumentTextLocation) {
        anchor = location
        current = location
        isDragging = true
    }

    /// Updates the live end of the drag. A no-op if no selection is active
    /// (defensive — the overlay is only ever supposed to call this after
    /// `beginSelection`).
    func extendSelection(to location: DocumentTextLocation) {
        guard isActive else { return }
        current = location
    }

    /// The finger lifted — the selection itself stays visible (handles
    /// included) until `cancel()` is called. A6 (tapping elsewhere cancels
    /// the selection) is wired from `CrossBlockSelectionCancelCatcher`, not
    /// from here.
    func endSelection() {
        isDragging = false
    }

    /// Clears the selection entirely.
    func cancel() {
        anchor = nil
        current = nil
        isDragging = false
    }

    /// The current normalized range, or `nil` while inactive, or if
    /// `order` no longer has one of the involved blocks (e.g. deleted
    /// mid-drag) — see `CrossBlockSelectionRange.make`'s doc comment for
    /// how this relates to A4.
    func range(order: BlockOrder) -> CrossBlockSelectionRange? {
        guard let anchor, let current else { return nil }
        return CrossBlockSelectionRange.make(anchor: anchor, current: current, order: order)
    }
}
