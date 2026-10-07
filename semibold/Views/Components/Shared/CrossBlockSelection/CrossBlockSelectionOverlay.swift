import SwiftUI
import UIKit

/// The custom drag-selection surface laid over `DetailScreen`'s block
/// list — a transparent `UIView` whose only job is hosting one
/// `UILongPressGestureRecognizer` that drives a `CrossBlockSelectionTracker`,
/// plus drawing that tracker's resulting highlight rects and two drag
/// handles once a selection exists.
///
/// **Deliberately one mechanism for both A2 (same-block drag) and A3
/// (drag crossing into other blocks)** — `tasks/NO-010.md` §4's "적용
/// 범위 확장" decision (2026-10-01). There is no separate code path that
/// only kicks in once a drag leaves its starting block; `Coordinator
/// .handleLongPress(_:)` calls the exact same
/// `CrossBlockSelectionHitTester.location(forPoint:in:candidates:)` →
/// `tracker.extendSelection(to:)` sequence on every `.changed` event,
/// whether the resolved location's `blockId` matches the previous one or
/// not.
///
/// **Deliberately NOT attached to any block's own `UITextView`** (an
/// earlier plan this brief's Decisions section rejected, in favor of one
/// overlay-level mechanism for every drag). See
/// `CrossBlockSelectionA1RegressionTests` for why a recognizer anywhere
/// near `IndentableTextView` itself would be exactly the kind of
/// regression that guard exists to catch. This overlay's recognizer has
/// `cancelsTouchesInView = false` and a delegate that always allows
/// simultaneous recognition, so every block's native tap-to-focus /
/// long-press-to-caret keeps working completely untouched underneath it
/// (A1) — this view only *also* watches the same touches, it never
/// prevents anything else from seeing them.
///
/// **What isn't validated by this type alone.** The coordinate-math half
/// of `tasks/NO-010.md` §4's required feasibility spike —
/// `closestPosition(to:)` converting a point into a character offset — is
/// unit-tested directly (`CrossBlockSelectionHitTesterTests`). The
/// gesture-recognizer half (whether this overlay's `UILongPressGestureRecognizer`
/// actually coexists cleanly with `UITextView`'s own *private* long-press/
/// pan recognizers at the exact moment a long-press turns into a drag,
/// without either one producing a visible flash of native selection UI)
/// is inherently a live-touch/responder-chain question this repo's
/// unit-test-only target can't simulate (same limitation
/// `CrossBlockSelectionA1RegressionTests`'s doc comment already describes
/// for A1). It needs manual/device verification — flagged here rather
/// than claimed as proven.
///
/// **A5 (auto-scroll near the viewport edge, selection keeps extending)**
/// lives in `Coordinator`'s "A5" section below, built on
/// `CrossBlockSelectionAutoScroller`/`CrossBlockSelectionAutoScrollZone` —
/// see those types' doc comments for the scroll-loop and edge-zone math,
/// and `findEnclosingOrSiblingScrollView()`'s doc comment for the one part
/// of A5 that reaches into `DetailScreen.blockList`'s SwiftUI `ScrollView`
/// through its UIKit backing view, the same "drop to UIKit where SwiftUI
/// can't do the job" pattern this overlay already uses for `UITextView`.
struct CrossBlockSelectionOverlay: UIViewRepresentable {
    var tracker: CrossBlockSelectionTracker
    var blockOrder: BlockOrder
    /// Called the moment a plain long-press turns into an actual
    /// drag-selection (movement crosses `Coordinator.dragThreshold`) —
    /// `DetailScreen` uses this to clear `focusedBlockId`, satisfying
    /// `CrossBlockSelection/README.md` common invariant 2 ("편집 모드와
    /// 선택 모드는 동시에 성립하지 않는다"). The reverse direction —
    /// tapping elsewhere cancels an active selection (A6) — is
    /// `CrossBlockSelectionCancelCatcher`'s job, not this type's.
    var onSelectionBegan: () -> Void

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.backgroundColor = .clear

        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:))
        )
        // Matches `UILongPressGestureRecognizer`'s own default — the same
        // duration iOS's native long-press-to-caret already uses, so this
        // overlay's `.began` fires at the same moment native caret
        // placement does, rather than noticeably before/after it.
        recognizer.minimumPressDuration = 0.5
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        context.coordinator.hostView = view
        context.coordinator.recognizer = recognizer
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refreshHighlights(in: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// The overlay's backing view — purely a transparent touch surface
    /// plus a place to park highlight/handle subviews
    /// (`render(highlights:)`). Carries no gesture logic of its own; that
    /// all lives on `Coordinator`, the same `UIViewRepresentable.Coordinator`
    /// split every other `UIViewRepresentable` in this app uses.
    final class HostView: UIView {
        private var highlightViews: [UIView] = []
        private let startHandle = SelectionHandleView()
        private let endHandle = SelectionHandleView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            addSubview(startHandle)
            addSubview(endHandle)
            startHandle.isHidden = true
            endHandle.isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func clearHighlights() {
            highlightViews.forEach { $0.removeFromSuperview() }
            highlightViews = []
            startHandle.isHidden = true
            endHandle.isHidden = true
        }

        /// Replaces every highlight/handle subview with ones matching
        /// `highlights` — `highlights` (and each highlight's own `rects`)
        /// are expected to already be in document order, so `rects.first`/
        /// `.last` across the flattened list are the selection's true
        /// start/end corners for handle placement.
        func render(highlights: [BlockSelectionHighlight]) {
            highlightViews.forEach { $0.removeFromSuperview() }
            highlightViews = []

            let allRects = highlights.flatMap(\.rects)
            guard let firstRect = allRects.first, let lastRect = allRects.last else {
                startHandle.isHidden = true
                endHandle.isHidden = true
                return
            }

            for rect in allRects {
                let highlightView = UIView(frame: rect)
                highlightView.backgroundColor = UIColor(AppTheme.Colors.accent).withAlphaComponent(0.25)
                highlightView.isUserInteractionEnabled = false
                insertSubview(highlightView, belowSubview: startHandle)
                highlightViews.append(highlightView)
            }

            startHandle.isHidden = false
            startHandle.center = CGPoint(x: firstRect.minX, y: firstRect.minY)
            endHandle.isHidden = false
            endHandle.center = CGPoint(x: lastRect.maxX, y: lastRect.maxY)
            bringSubviewToFront(startHandle)
            bringSubviewToFront(endHandle)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CrossBlockSelectionOverlay
        weak var hostView: HostView?
        /// The overlay's own long-press recognizer — held so an in-flight
        /// auto-scroll tick (A5) can read the drag's *live* touch point
        /// directly off it (`UIGestureRecognizer.location(in:)` reflects
        /// the current touch at any time it's called, not just inside a
        /// delivered `.changed` action). That matters here because the
        /// user's finger can sit completely still at the viewport's edge
        /// for the whole auto-scroll — no further `.changed` events fire
        /// at all while it doesn't move, so a stored "last point" captured
        /// only from `.changed` would go stale the moment scrolling starts.
        weak var recognizer: UILongPressGestureRecognizer?

        /// Drives A5's "auto-scroll near the viewport edge, selection keeps
        /// extending while it does" behavior — see
        /// `CrossBlockSelectionAutoScroller`'s doc comment.
        private let autoScroller = CrossBlockSelectionAutoScroller()

        /// The touch-down point, recorded on `.began`, so `.changed` can
        /// measure total movement against `dragThreshold` before treating
        /// this as a real drag-selection rather than a stationary
        /// long-press (A1's "빈 커서만 놓인다" case — this overlay must
        /// stay inert for that case, not just visually but by never
        /// calling into `tracker` at all).
        private var pressDownPoint: CGPoint?
        private var hasStartedDragging = false

        /// Matches `UILongPressGestureRecognizer.allowableMovement`'s own
        /// default (10pt) — once the finger has moved this far from where
        /// it first went down, this reads as an intentional drag rather
        /// than a stationary long-press.
        let dragThreshold: CGFloat = 10

        init(_ parent: CrossBlockSelectionOverlay) {
            self.parent = parent
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Always `true` — this overlay's recognizer only ever observes
            // touches alongside whatever native recognizer (tap-to-focus,
            // long-press-to-caret, the pan that scrolls the block list)
            // would otherwise handle them; it never competes for exclusive
            // ownership of a touch.
            true
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let hostView else { return }
            let point = recognizer.location(in: hostView)

            switch recognizer.state {
            case .began:
                pressDownPoint = point
                hasStartedDragging = false

            case .changed:
                guard let pressDownPoint else { return }
                if !hasStartedDragging {
                    let distance = hypot(point.x - pressDownPoint.x, point.y - pressDownPoint.y)
                    guard distance >= dragThreshold else { return }
                    hasStartedDragging = true
                    guard let anchorLocation = resolveLocation(at: pressDownPoint, in: hostView) else {
                        hasStartedDragging = false
                        return
                    }
                    parent.tracker.beginSelection(at: anchorLocation)
                    parent.onSelectionBegan()
                }
                guard let currentLocation = resolveLocation(at: point, in: hostView) else { return }
                parent.tracker.extendSelection(to: currentLocation)
                refreshHighlights(in: hostView)
                updateAutoScroll(at: point, in: hostView)

            case .ended, .cancelled, .failed:
                if hasStartedDragging {
                    parent.tracker.endSelection()
                }
                pressDownPoint = nil
                hasStartedDragging = false
                autoScroller.stop()

            default:
                break
            }
        }

        /// Re-renders `hostView`'s highlight/handle subviews from
        /// `tracker`'s current state — called both from the gesture
        /// handler above (every `.changed` event, so highlights track the
        /// drag live) and from `updateUIView` (so a change to `tracker`
        /// from elsewhere, or to `parent.blockOrder` as blocks are
        /// inserted/removed, is picked up too).
        func refreshHighlights(in hostView: HostView) {
            guard let range = parent.tracker.range(order: parent.blockOrder) else {
                hostView.clearHighlights()
                return
            }
            let candidates = parent.blockOrder.blockIds.compactMap { blockId -> (blockId: String, textView: UITextView)? in
                guard let textView = BlockTextViewRegistry.shared.textView(for: blockId) else { return nil }
                return (blockId, textView)
            }
            let highlights = CrossBlockSelectionHighlightGeometry.highlights(
                for: range, order: parent.blockOrder, candidates: candidates, in: hostView
            )
            hostView.render(highlights: highlights)
        }

        private func resolveLocation(at point: CGPoint, in coordinateSpace: UIView) -> DocumentTextLocation? {
            let candidates = parent.blockOrder.blockIds.compactMap { blockId -> (blockId: String, textView: UITextView)? in
                guard let textView = BlockTextViewRegistry.shared.textView(for: blockId) else { return nil }
                return (blockId, textView)
            }
            return CrossBlockSelectionHitTester.location(forPoint: point, in: coordinateSpace, candidates: candidates)
        }

        // MARK: - A5: auto-scroll near the viewport edge

        /// Starts the auto-scroll loop the moment `point` enters an edge
        /// zone, stops it the moment `point` leaves one — called on every
        /// `.changed` event, after that event's own selection update above.
        /// A no-op if the loop is already running for an active zone;
        /// `performAutoScrollTick()` re-resolves the zone itself on every
        /// tick, so there's nothing here that needs "re-targeting" as the
        /// point moves further into/out of the same edge.
        private func updateAutoScroll(at point: CGPoint, in hostView: HostView) {
            let zone = CrossBlockSelectionAutoScrollZone.resolve(
                touchY: point.y,
                viewportHeight: hostView.bounds.height
            )
            guard zone.isActive else {
                autoScroller.stop()
                return
            }
            guard !autoScroller.isRunning else { return }
            autoScroller.start { [weak self] in
                self?.performAutoScrollTick() ?? false
            }
        }

        /// One auto-scroll tick (`CrossBlockSelectionAutoScroller`'s
        /// `onTick`). Re-reads the drag's live touch point straight from
        /// `recognizer` (not a point captured back when `.changed` last
        /// fired) since the finger can sit still at the edge for the whole
        /// scroll — see `recognizer`'s own doc comment for why that matters.
        /// Returns `false` (stop ticking) the instant the drag has ended or
        /// the touch has left the edge zone, `true` to keep going.
        private func performAutoScrollTick() -> Bool {
            guard
                hasStartedDragging,
                let hostView,
                let recognizer,
                recognizer.state == .began || recognizer.state == .changed
            else { return false }

            let point = recognizer.location(in: hostView)
            let zone = CrossBlockSelectionAutoScrollZone.resolve(
                touchY: point.y,
                viewportHeight: hostView.bounds.height
            )
            guard zone.isActive else { return false }

            if let scrollView = hostView.findEnclosingOrSiblingScrollView() {
                scrollView.applyCrossBlockSelectionAutoScrollDelta(zone.contentOffsetDelta)
            }

            // Re-resolve the selection now that new rows may have scrolled
            // into view and registered with `BlockTextViewRegistry` since
            // the last tick — this is what keeps the selection "계속
            // 연장" (A5) as the document moves under a stationary finger.
            if let location = resolveLocation(at: point, in: hostView) {
                parent.tracker.extendSelection(to: location)
                refreshHighlights(in: hostView)
            }
            return true
        }
    }
}

/// One of the two drag handles shown at a cross-block selection's start/end
/// corners, matching the `iOS_Editor_MultiBlockSelection` Figma frame's
/// handle style.
///
/// **Visual design gap, flagged rather than guessed at silently
/// (CLAUDE.md §0's "말하지 않고 임의로 개선하지 않는다" rule)** — this
/// implementation session had no working Figma MCP connection, so this
/// handle's exact size/shape/color couldn't be read from
/// `iOS_Editor_MultiBlockSelection` directly. It uses `AppTheme.Colors
/// .accent` (not a hardcoded hex value, per CLAUDE.md §3) as a reasonable
/// placeholder matching iOS's own native selection-handle color
/// convention, sized to `AppTheme.Spacing.sm` (8pt) as its diameter. This
/// needs a design pass against the actual Figma frame before this AC item
/// ("선택 하이라이트/드래그 핸들의 시각적 배치가 … 디자인과 일치한다")
/// can be marked done.
private final class SelectionHandleView: UIView {
    init() {
        let diameter = AppTheme.Spacing.sm
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        backgroundColor = UIColor(AppTheme.Colors.accent)
        layer.cornerRadius = diameter / 2
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
