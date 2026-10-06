import Testing
import UIKit

@testable import semibold

/// Tests for A5 ("드래그 지점이 화면 위/아래 가장자리에 닿으면 자동
/// 스크롤되며, 스크롤 중에도 선택 범위가 계속 연장된다") — covering the
/// parts of `CrossBlockSelectionAutoScrollZone`/`CrossBlockSelectionAutoScroller`/
/// `UIScrollView.applyCrossBlockSelectionAutoScrollDelta(_:)`/
/// `UIView.findEnclosingOrSiblingScrollView()` that don't need a live
/// touch or a hosted window to verify.
///
/// **Why this doesn't simulate an actual auto-scrolling drag.** Same
/// limitation every other file in this directory documents (no XCUITest
/// target, no live window/responder chain) — plus this scenario adds a
/// `DetailScreen`-specific question on top: whether
/// `findEnclosingOrSiblingScrollView()` actually finds
/// `DetailScreen.blockList`'s real `UIScrollView` at runtime, given exactly
/// how SwiftUI composes `ScrollView` + `.overlay(...)` into UIKit views.
/// That composition is entirely a runtime/SwiftUI-internals question this
/// unit-test target has no way to observe — this suite only confirms the
/// traversal algorithm itself is correct against a hierarchy shaped the way
/// the doc comment on `findEnclosingOrSiblingScrollView()` describes.
/// **Needs manual/device verification** before A5 can be called fully
/// proven, the same way the native-vs-custom long-press race condition
/// was flagged for AC2/AC3 rather than claimed as proven from unit tests
/// alone.
@MainActor
struct CrossBlockSelectionAutoScrollTests {
    // MARK: - CrossBlockSelectionAutoScrollZone.resolve(...) — pure edge-zone math

    @Test("A touch in the viewport's middle resolves to no auto-scroll zone")
    func middleOfViewportIsNoZone() {
        let zone = CrossBlockSelectionAutoScrollZone.resolve(
            touchY: 400, viewportHeight: 800, edgeThickness: 40, maxSpeed: 14
        )
        #expect(zone == .none)
    }

    @Test("A touch right at the top edge resolves to the top zone at maximum speed")
    func touchAtTopEdgeIsMaxSpeed() {
        let zone = CrossBlockSelectionAutoScrollZone.resolve(
            touchY: 0, viewportHeight: 800, edgeThickness: 40, maxSpeed: 14
        )
        #expect(zone == .top(speed: 14))
    }

    @Test("A touch right at the bottom edge resolves to the bottom zone at maximum speed")
    func touchAtBottomEdgeIsMaxSpeed() {
        let zone = CrossBlockSelectionAutoScrollZone.resolve(
            touchY: 800, viewportHeight: 800, edgeThickness: 40, maxSpeed: 14
        )
        #expect(zone == .bottom(speed: 14))
    }

    @Test("A touch halfway into the top edge zone scrolls at half speed — deeper into the edge is faster")
    func touchHalfwayIntoTopZoneIsHalfSpeed() {
        let zone = CrossBlockSelectionAutoScrollZone.resolve(
            touchY: 20, viewportHeight: 800, edgeThickness: 40, maxSpeed: 14
        )
        #expect(zone == .top(speed: 7))
    }

    @Test("A touch halfway into the bottom edge zone scrolls at half speed")
    func touchHalfwayIntoBottomZoneIsHalfSpeed() {
        let zone = CrossBlockSelectionAutoScrollZone.resolve(
            touchY: 780, viewportHeight: 800, edgeThickness: 40, maxSpeed: 14
        )
        #expect(zone == .bottom(speed: 7))
    }

    @Test("A touch just outside the edge zone (1pt further in) is not in a zone at all")
    func touchJustOutsideEdgeZoneIsNoZone() {
        let zone = CrossBlockSelectionAutoScrollZone.resolve(
            touchY: 41, viewportHeight: 800, edgeThickness: 40, maxSpeed: 14
        )
        #expect(zone == .none)
    }

    @Test("A touch that has drifted above the viewport's own top edge still resolves to the top zone at max speed")
    func touchAboveViewportClampsToTopMaxSpeed() {
        let zone = CrossBlockSelectionAutoScrollZone.resolve(
            touchY: -50, viewportHeight: 800, edgeThickness: 40, maxSpeed: 14
        )
        #expect(zone == .top(speed: 14))
    }

    @Test("A touch that has drifted below the viewport's own bottom edge still resolves to the bottom zone at max speed")
    func touchBelowViewportClampsToBottomMaxSpeed() {
        let zone = CrossBlockSelectionAutoScrollZone.resolve(
            touchY: 900, viewportHeight: 800, edgeThickness: 40, maxSpeed: 14
        )
        #expect(zone == .bottom(speed: 14))
    }

    @Test("An invalid viewport (zero height) never resolves to an active zone, regardless of touch position")
    func zeroHeightViewportIsAlwaysNoZone() {
        let zone = CrossBlockSelectionAutoScrollZone.resolve(
            touchY: 0, viewportHeight: 0, edgeThickness: 40, maxSpeed: 14
        )
        #expect(zone == .none)
    }

    @Test("contentOffsetDelta is negative for .top, positive for .bottom, zero for .none")
    func contentOffsetDeltaSignsMatchDirection() {
        #expect(CrossBlockSelectionAutoScrollZone.top(speed: 10).contentOffsetDelta == -10)
        #expect(CrossBlockSelectionAutoScrollZone.bottom(speed: 10).contentOffsetDelta == 10)
        #expect(CrossBlockSelectionAutoScrollZone.none.contentOffsetDelta == 0)
    }

    // MARK: - UIScrollView.applyCrossBlockSelectionAutoScrollDelta(_:)

    private func makeScrollView(contentHeight: CGFloat, viewportHeight: CGFloat, offsetY: CGFloat) -> UIScrollView {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: viewportHeight))
        scrollView.contentSize = CGSize(width: 300, height: contentHeight)
        scrollView.contentOffset = CGPoint(x: 0, y: offsetY)
        return scrollView
    }

    @Test("A negative delta (top zone) scrolls content up, decreasing contentOffset.y")
    func negativeDeltaScrollsUp() {
        let scrollView = makeScrollView(contentHeight: 2000, viewportHeight: 800, offsetY: 500)

        scrollView.applyCrossBlockSelectionAutoScrollDelta(-14)

        #expect(scrollView.contentOffset.y == 486)
    }

    @Test("A positive delta (bottom zone) scrolls content down, increasing contentOffset.y")
    func positiveDeltaScrollsDown() {
        let scrollView = makeScrollView(contentHeight: 2000, viewportHeight: 800, offsetY: 500)

        scrollView.applyCrossBlockSelectionAutoScrollDelta(14)

        #expect(scrollView.contentOffset.y == 514)
    }

    @Test("Scrolling up never goes past contentOffset.y == 0, even if the delta would overshoot")
    func upwardScrollClampsAtZero() {
        let scrollView = makeScrollView(contentHeight: 2000, viewportHeight: 800, offsetY: 5)

        scrollView.applyCrossBlockSelectionAutoScrollDelta(-14)

        #expect(scrollView.contentOffset.y == 0)
    }

    @Test("Scrolling down never goes past the content's bottom edge, even if the delta would overshoot")
    func downwardScrollClampsAtContentBottom() {
        // maxOffsetY = contentHeight - viewportHeight = 2000 - 800 = 1200
        let scrollView = makeScrollView(contentHeight: 2000, viewportHeight: 800, offsetY: 1195)

        scrollView.applyCrossBlockSelectionAutoScrollDelta(14)

        #expect(scrollView.contentOffset.y == 1200)
    }

    @Test("Content shorter than the viewport never scrolls at all — maxOffsetY clamps to 0")
    func contentShorterThanViewportNeverScrolls() {
        let scrollView = makeScrollView(contentHeight: 400, viewportHeight: 800, offsetY: 0)

        scrollView.applyCrossBlockSelectionAutoScrollDelta(14)

        #expect(scrollView.contentOffset.y == 0)
    }

    @Test("A zero delta is a no-op")
    func zeroDeltaIsNoOp() {
        let scrollView = makeScrollView(contentHeight: 2000, viewportHeight: 800, offsetY: 500)

        scrollView.applyCrossBlockSelectionAutoScrollDelta(0)

        #expect(scrollView.contentOffset.y == 500)
    }

    // MARK: - CrossBlockSelectionAutoScroller — the repeating tick loop

    @Test("start(onTick:) ticks repeatedly until onTick returns false")
    func autoScrollerTicksUntilOnTickReturnsFalse() async throws {
        let scroller = CrossBlockSelectionAutoScroller()
        var tickCount = 0

        scroller.start(tickInterval: .milliseconds(1)) {
            tickCount += 1
            return tickCount < 5
        }

        // The same "sleep past the expected settle time, then assert"
        // pattern `SidebarDrawerViewModelTests` already uses for its own
        // `Task.sleep`-based debounce — 1ms ticks settle well within this
        // window.
        try await Task.sleep(for: .milliseconds(50))

        #expect(tickCount == 5)
        #expect(scroller.isRunning == false)
    }

    @Test("stop() halts the loop before onTick would naturally return false")
    func stopHaltsLoopEarly() async {
        let scroller = CrossBlockSelectionAutoScroller()
        var tickCount = 0

        scroller.start(tickInterval: .milliseconds(1)) {
            tickCount += 1
            return true // would tick forever if not stopped
        }

        try? await Task.sleep(for: .milliseconds(20))
        scroller.stop()
        let countAtStop = tickCount

        try? await Task.sleep(for: .milliseconds(20))

        #expect(scroller.isRunning == false)
        // No further ticks happened after `stop()` — the loop's `Task` was
        // actually cancelled, not just asked nicely to stop next time.
        #expect(tickCount == countAtStop)
    }

    @Test("A second start(onTick:) call while already running is a no-op — it doesn't start a second concurrent loop")
    func secondStartWhileRunningIsNoOp() async {
        let scroller = CrossBlockSelectionAutoScroller()
        var firstLoopTicks = 0
        var secondLoopTicks = 0

        scroller.start(tickInterval: .milliseconds(1)) {
            firstLoopTicks += 1
            return firstLoopTicks < 10
        }
        scroller.start(tickInterval: .milliseconds(1)) {
            secondLoopTicks += 1
            return true
        }

        try? await Task.sleep(for: .milliseconds(50))

        #expect(firstLoopTicks > 0)
        #expect(secondLoopTicks == 0)
    }

    // MARK: - UIView.findEnclosingOrSiblingScrollView() — view-tree traversal

    @Test("Finds a UIScrollView that's a direct ancestor of the starting view")
    func findsDirectAncestorScrollView() {
        let scrollView = UIScrollView()
        let child = UIView()
        scrollView.addSubview(child)

        #expect(child.findEnclosingOrSiblingScrollView() === scrollView)
    }

    @Test("Finds a UIScrollView that's a sibling's descendant, not a direct ancestor — the shape this overlay actually expects")
    func findsSiblingDescendantScrollView() {
        let root = UIView()
        let overlayContainer = UIView()
        let scrollViewContainer = UIView()
        let scrollView = UIScrollView()
        let hostView = UIView()

        root.addSubview(overlayContainer)
        root.addSubview(scrollViewContainer)
        overlayContainer.addSubview(hostView)
        scrollViewContainer.addSubview(scrollView)

        #expect(hostView.findEnclosingOrSiblingScrollView() === scrollView)
    }

    @Test("Returns nil when no UIScrollView exists anywhere in range")
    func returnsNilWhenNoScrollViewExists() {
        let root = UIView()
        let child = UIView()
        root.addSubview(child)

        #expect(child.findEnclosingOrSiblingScrollView() == nil)
    }

    @Test("Returns nil once maxAncestorHops is exhausted, even if a UIScrollView exists further up")
    func returnsNilBeyondHopLimit() {
        var current = UIView()
        let leaf = current
        // Stack up more ancestor levels than the hop limit allows before
        // finally adding a UIScrollView at the very top.
        for _ in 0..<5 {
            let next = UIView()
            next.addSubview(current)
            current = next
        }
        let scrollView = UIScrollView()
        scrollView.addSubview(current)

        #expect(leaf.findEnclosingOrSiblingScrollView(maxAncestorHops: 2) == nil)
        #expect(leaf.findEnclosingOrSiblingScrollView(maxAncestorHops: 10) === scrollView)
    }
}
