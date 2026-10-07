import UIKit

/// A5's pure "is the drag near an edge, and how fast should that scroll"
/// decision — `CrossBlockSelection/README.md`: "드래그 지점이 화면 위/아래
/// 가장자리 뷰포트에 닿으면 자동으로 스크롤되고". Deliberately has no idea
/// about `UIScrollView`, gesture recognizers, or timers — just a touch
/// point and a viewport height in, a direction/speed out — so it's testable
/// with plain numbers (`CrossBlockSelectionAutoScrollZoneTests`) the same
/// way `CrossBlockSelectionHitTester`'s coordinate math is.
enum CrossBlockSelectionAutoScrollZone: Equatable {
    case none
    /// Scroll toward the document's start (content moves down, earlier
    /// blocks come into view). `speed` is a signed-magnitude points-per-tick
    /// value, already scaled by how deep into the edge zone the touch is.
    case top(speed: CGFloat)
    /// Scroll toward the document's end. Same `speed` convention as `.top`.
    case bottom(speed: CGFloat)

    var isActive: Bool { self != .none }

    /// How close to the viewport's top/bottom edge counts as "near enough
    /// to auto-scroll" — reuses the spacing scale's `xxl` (40pt) rather
    /// than a bespoke magic number, since this is a touch-target-sized
    /// zone, the same kind of value `AppTheme.Spacing` already catalogs.
    static let defaultEdgeThickness: CGFloat = AppTheme.Spacing.xxl

    /// The fastest this auto-scroll ever moves, in points per tick
    /// (`CrossBlockSelectionAutoScroller.tickInterval` apart) — reached
    /// right at the viewport's edge, tapering to 0 at `defaultEdgeThickness`
    /// away from it. Not an `AppTheme` token (unlike `defaultEdgeThickness`)
    /// — this is a gesture-feel tuning constant, not a design value, the
    /// same category `CrossBlockSelectionOverlay.Coordinator.dragThreshold`
    /// already is.
    static let defaultMaxSpeed: CGFloat = 14

    /// `touchY`/`viewportHeight` are both in the same coordinate space —
    /// in practice `CrossBlockSelectionOverlay.HostView`'s own bounds,
    /// which always matches the scroll view's visible viewport (the
    /// overlay sits directly over `DetailScreen.blockList`'s frame).
    ///
    /// A touch that's drifted entirely outside the viewport (UIKit still
    /// reports `location(in:)` for a touch that moves past a tracking
    /// view's own bounds) clamps to that edge's `maxSpeed` outright, rather
    /// than reading as "no zone" — dragging up past the block list into the
    /// title area, or down past it toward the keyboard, should still feel
    /// like "hugging the edge," not like leaving the zone entirely.
    static func resolve(
        touchY: CGFloat,
        viewportHeight: CGFloat,
        edgeThickness: CGFloat = defaultEdgeThickness,
        maxSpeed: CGFloat = defaultMaxSpeed
    ) -> CrossBlockSelectionAutoScrollZone {
        guard viewportHeight > 0, edgeThickness > 0, maxSpeed > 0 else { return .none }

        if touchY < 0 { return .top(speed: maxSpeed) }
        if touchY > viewportHeight { return .bottom(speed: maxSpeed) }

        if touchY <= edgeThickness {
            let depth = (edgeThickness - touchY) / edgeThickness
            return .top(speed: maxSpeed * depth)
        }
        if touchY >= viewportHeight - edgeThickness {
            let depth = (touchY - (viewportHeight - edgeThickness)) / edgeThickness
            return .bottom(speed: maxSpeed * depth)
        }
        return .none
    }

    /// Signed per-tick content-offset delta this zone implies — negative
    /// (scroll content down, reveal earlier blocks) for `.top`, positive
    /// for `.bottom`, zero for `.none`. What `UIScrollView
    /// .applyCrossBlockSelectionAutoScrollDelta(_:)` below actually applies.
    var contentOffsetDelta: CGFloat {
        switch self {
        case .none: return 0
        case .top(let speed): return -speed
        case .bottom(let speed): return speed
        }
    }
}

extension UIScrollView {
    /// Applies one A5 auto-scroll tick's offset delta, clamped so the
    /// content never scrolls past its own top or bottom edge — a `delta`
    /// that would overshoot just clamps to that edge instead of being
    /// dropped, so a drag held past the last reachable scroll position
    /// still settles exactly at the edge rather than stopping one tick
    /// short of it.
    func applyCrossBlockSelectionAutoScrollDelta(_ delta: CGFloat) {
        guard delta != 0 else { return }
        let maxOffsetY = max(0, contentSize.height - bounds.height)
        let newOffsetY = min(max(contentOffset.y + delta, 0), maxOffsetY)
        guard newOffsetY != contentOffset.y else { return }
        setContentOffset(CGPoint(x: contentOffset.x, y: newOffsetY), animated: false)
    }
}

/// Drives A5's "keep scrolling, and keep extending the selection, for as
/// long as the touch stays in the edge zone" behavior with a repeating
/// `Task.sleep` loop — the same cancel-and-reschedule concurrency pattern
/// `SidebarDrawerViewModel`'s search debounce and `DetailViewModel`'s
/// autosave debounce already use in this codebase, rather than introducing
/// `Timer`/`CADisplayLink` as a new mechanism for just this one feature.
///
/// Deliberately knows nothing about `UIScrollView`, `CrossBlockSelectionTracker`,
/// or gesture recognizers itself — `onTick` (supplied by
/// `CrossBlockSelectionOverlay.Coordinator`) is the only point of contact
/// with the outside world. That keeps this type testable with a plain
/// counting closure (`CrossBlockSelectionAutoScrollerTests`) instead of a
/// real scroll view and mounted text views, the same "extract the pure/
/// testable half, document what can't be tested here" split this branch's
/// other engine types already follow.
@MainActor
final class CrossBlockSelectionAutoScroller {
    /// How often a tick fires. Fast enough to read as continuous motion,
    /// not so fast it re-runs a hit-test + highlight refresh needlessly
    /// often on the main thread.
    static let tickInterval: Duration = .milliseconds(33) // ~30 ticks/sec

    private var loopTask: Task<Void, Never>?

    /// Whether a scroll loop is currently ticking.
    var isRunning: Bool { loopTask != nil }

    /// Starts ticking — a no-op if already running, since a tick already
    /// in flight will pick up any change in conditions (the touch moving
    /// further into/out of the zone) the next time it fires; there's no
    /// need to tear down and restart the loop itself. `onTick` runs once
    /// per tick and returns whether to keep going (`true`) or stop itself
    /// (`false` — e.g. the drag ended, or the touch left the edge zone).
    func start(tickInterval: Duration = tickInterval, onTick: @escaping () -> Bool) {
        guard loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard onTick() else { break }
                try? await Task.sleep(for: tickInterval)
            }
            self?.loopTask = nil
        }
    }

    /// Stops ticking immediately — called the moment the drag ends, or the
    /// touch moves back out of the edge zone.
    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }
}

extension UIView {
    /// Finds the `UIScrollView` backing `DetailScreen.blockList`'s SwiftUI
    /// `ScrollView` — reached by walking outward through ancestor
    /// containers and searching each one's full subtree at every step,
    /// rather than assuming `self` (in practice
    /// `CrossBlockSelectionOverlay.HostView`) sits literally *inside* that
    /// `UIScrollView`'s own subview chain.
    ///
    /// **Why not just walk `superview` looking for a `UIScrollView`
    /// directly?** An overlay that must stay fixed on screen while its
    /// base view's content scrolls underneath it is, in practice, the kind
    /// of thing SwiftUI is more likely to position as a sibling layer next
    /// to the scroll view (both inside some shared container) than as a
    /// subview *of* the scroll view's own scrolling content — if it were
    /// scrolled content, the overlay itself would scroll away instead of
    /// staying put, which is observably not what happens today. Searching
    /// each ancestor level's full subtree (not just the direct ancestor
    /// chain) finds the scroll view whichever of those two shapes SwiftUI
    /// actually produces.
    ///
    /// **This traversal's own logic is unit-tested** against a synthetic
    /// `UIView` hierarchy (`CrossBlockSelectionAutoScrollViewTraversalTests`)
    /// — confirming it correctly finds a `UIScrollView` that's a sibling's
    /// descendant, not just a direct ancestor. **What that can't confirm**
    /// is which shape SwiftUI's real `ScrollView` + `.overlay(...)`
    /// composition actually produces in this app at runtime — this repo
    /// has no hosted-window test target to inspect that live view
    /// hierarchy, so this needs manual/device verification (the same
    /// "flagged, not silently assumed" caveat `CrossBlockSelectionOverlay`'s
    /// doc comment already carries for its own gesture-recognizer
    /// coexistence question).
    func findEnclosingOrSiblingScrollView(maxAncestorHops: Int = 8) -> UIScrollView? {
        var candidate: UIView? = self
        var hopsRemaining = maxAncestorHops
        while let current = candidate, hopsRemaining > 0 {
            if let found = current.firstScrollViewInSubtree() {
                return found
            }
            candidate = current.superview
            hopsRemaining -= 1
        }
        return nil
    }

    private func firstScrollViewInSubtree() -> UIScrollView? {
        if let scrollView = self as? UIScrollView { return scrollView }
        for subview in subviews {
            if let found = subview.firstScrollViewInSubtree() {
                return found
            }
        }
        return nil
    }
}
