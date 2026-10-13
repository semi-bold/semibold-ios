import Testing
import UIKit

@testable import semibold

/// Tests for A6 ("선택 도중 다른 화면 요소를 탭함") and the "tapping
/// elsewhere cancels an active selection" half of common invariant 2
/// ("편집 모드와 선택 모드는 동시에 성립하지 않는다") —
/// `CrossBlockSelectionCancelCatcher`'s `Coordinator.handleTap()`, plus the
/// `Coordinator.attach(to:)`/`detach()` pair that puts the real
/// `UITapGestureRecognizer` on the `UIWindow` hosting `DetailScreen`.
///
/// **Why this doesn't simulate an actual tap landing on the nav bar, a
/// block, or anywhere else.** Same limitation every other file in this
/// directory documents (no XCUITest target, no live app/responder chain to
/// deliver a real touch through). `handleTap()` itself takes no
/// gesture-recognizer argument at all — unlike `CrossBlockSelectionOverlay
/// .Coordinator.handleLongPress(_:)`, it never reads a touch location or
/// gesture state — so it's directly callable here exactly the way UIKit
/// would call it once a `UITapGestureRecognizer` actually recognizes a tap.
/// What these tests can't cover: whether a live, finger-driven tap on the
/// nav bar/title area/a block actually gets delivered to a recognizer
/// attached to the window, end to end, inside this app's actual compiled
/// view hierarchy — that still needs manual/device verification.
///
/// **What *is* now provable without a live touch, by construction.**
/// `attach(to:)`/`detach()` only depend on `UIWindow`/`UIView.window`,
/// which — unlike SwiftUI's `.background()`/`.overlay()` composition — are
/// plain, documented UIKit mechanics: `addSubview(_:)` sets a view's
/// `window` to its new ancestor window synchronously, with no running app
/// or key/visible window required, and a `UIGestureRecognizer` attached to
/// a `UIView` (including a `UIWindow`) fires for a touch that hit-tests to
/// that view *or any descendant of it*, regardless of nesting depth. The
/// tests below construct exactly that kind of synthetic
/// `UIWindow` → … → marker-view hierarchy (mirroring how
/// `CrossBlockSelectionAutoScrollTests`' `findEnclosingOrSiblingScrollView`
/// tests build a synthetic `UIView` tree) and confirm: the window is the
/// one place the recognizer ends up regardless of how deep the marker is
/// nested under it, attaching never leaves more than one live recognizer
/// behind, and detaching (or moving to a `nil`/different window) actually
/// removes it. That closes the specific architectural gap the two earlier
/// attempts at this got wrong (`.background()` risking a sibling branch,
/// `.overlay{}` risking this view winning `hitTest(_:with:)` outright) —
/// what's left unverified is purely "does UIKit deliver a live finger
/// touch the way its own documented rules say it will," not "is this
/// screen-wide reach architecturally sound."
@MainActor
struct CrossBlockSelectionCancelTests {
    // MARK: - A6: a tap cancels an active selection

    @Test("A6: a tap while a selection is active (drag already ended) cancels it")
    func tapCancelsActiveSelection() {
        let tracker = CrossBlockSelectionTracker()
        tracker.beginSelection(at: DocumentTextLocation(blockId: "a", offset: 0))
        tracker.extendSelection(to: DocumentTextLocation(blockId: "b", offset: 3))
        tracker.endSelection()
        #expect(tracker.isActive == true)

        let coordinator = CrossBlockSelectionCancelCatcher.Coordinator(tracker: tracker)
        coordinator.handleTap()

        #expect(tracker.isActive == false)
        #expect(tracker.anchor == nil)
        #expect(tracker.current == nil)
    }

    @Test("A6: a tap with no active selection is a harmless no-op")
    func tapWithNoActiveSelectionIsNoOp() {
        let tracker = CrossBlockSelectionTracker()
        let coordinator = CrossBlockSelectionCancelCatcher.Coordinator(tracker: tracker)

        coordinator.handleTap()

        #expect(tracker.isActive == false)
        #expect(tracker.isDragging == false)
    }

    @Test("A6: a tap that lands mid-drag (isDragging still true) does not cancel the selection it's part of")
    func tapDuringLiveDragDoesNotCancel() {
        // Guards the belt-and-suspenders check in `handleTap()` — in
        // practice a plain `UITapGestureRecognizer` fails to recognize at
        // all once real drag movement happens, so `handleTap()` shouldn't
        // even be called for this touch; this test pins the fallback
        // behavior in case that assumption is ever wrong.
        let tracker = CrossBlockSelectionTracker()
        tracker.beginSelection(at: DocumentTextLocation(blockId: "a", offset: 0))
        tracker.extendSelection(to: DocumentTextLocation(blockId: "b", offset: 3))
        #expect(tracker.isDragging == true)

        let coordinator = CrossBlockSelectionCancelCatcher.Coordinator(tracker: tracker)
        coordinator.handleTap()

        #expect(tracker.isActive == true)
        #expect(tracker.isDragging == true)
    }

    // swiftlint:disable:next line_length
    @Test("A6-a: canceling a selection (a tap on a different block) leaves the tracker ready for a brand-new drag right away")
    func cancelThenNewSelectionStartsCleanly() {
        let tracker = CrossBlockSelectionTracker()
        tracker.beginSelection(at: DocumentTextLocation(blockId: "a", offset: 0))
        tracker.extendSelection(to: DocumentTextLocation(blockId: "b", offset: 3))
        tracker.endSelection()

        CrossBlockSelectionCancelCatcher.Coordinator(tracker: tracker).handleTap()
        #expect(tracker.isActive == false)

        // The tapped block's own native tap-to-focus (untouched by this
        // type — see its doc comment) is what actually moves typing focus
        // there; this half just confirms cancelling leaves no stale state
        // behind that could confuse the very next drag-selection a user
        // starts on that newly focused block.
        tracker.beginSelection(at: DocumentTextLocation(blockId: "c", offset: 1))
        #expect(tracker.anchor == DocumentTextLocation(blockId: "c", offset: 1))
        #expect(tracker.current == DocumentTextLocation(blockId: "c", offset: 1))
    }

    // MARK: - Window-ancestor attachment (`Coordinator.attach(to:)`/`detach()`)

    /// A bare `UIWindow()` already carries its own system gesture
    /// recognizers (including, in this test environment, at least one
    /// `UITapGestureRecognizer` of its own) even before this type ever
    /// touches it — so these tests check whether `window.gestureRecognizers`
    /// contains *this specific recognizer instance* (by identity), rather
    /// than counting recognizers by type or assuming the array starts
    /// empty.
    private func isAttached(_ recognizer: UITapGestureRecognizer?, to window: UIWindow) -> Bool {
        guard let recognizer else { return false }
        return window.gestureRecognizers?.contains { $0 === recognizer } ?? false
    }

    @Test("attach(to:) puts this coordinator's own recognizer on the given window")
    func attachAddsOneRecognizerToWindow() {
        let window = UIWindow()
        let coordinator = CrossBlockSelectionCancelCatcher.Coordinator(tracker: CrossBlockSelectionTracker())

        coordinator.attach(to: window)

        #expect(coordinator.recognizer != nil)
        #expect(isAttached(coordinator.recognizer, to: window))
        #expect(coordinator.attachedWindow === window)
    }

    @Test("attach(to:) replaces its own previous recognizer rather than leaving stale ones behind")
    func attachIsIdempotentForTheSameWindow() {
        let window = UIWindow()
        let coordinator = CrossBlockSelectionCancelCatcher.Coordinator(tracker: CrossBlockSelectionTracker())

        coordinator.attach(to: window)
        let firstRecognizer = coordinator.recognizer

        coordinator.attach(to: window)
        coordinator.attach(to: window)
        let finalRecognizer = coordinator.recognizer

        #expect(firstRecognizer !== finalRecognizer)
        #expect(!isAttached(firstRecognizer, to: window))
        #expect(isAttached(finalRecognizer, to: window))
    }

    @Test("attach(to:) moves the recognizer off a previous window when the marker reaches a new one")
    func attachMovesRecognizerToNewWindow() {
        let firstWindow = UIWindow()
        let secondWindow = UIWindow()
        let coordinator = CrossBlockSelectionCancelCatcher.Coordinator(tracker: CrossBlockSelectionTracker())

        coordinator.attach(to: firstWindow)
        let firstRecognizer = coordinator.recognizer
        #expect(isAttached(firstRecognizer, to: firstWindow))

        coordinator.attach(to: secondWindow)

        #expect(!isAttached(firstRecognizer, to: firstWindow))
        #expect(isAttached(coordinator.recognizer, to: secondWindow))
        #expect(coordinator.attachedWindow === secondWindow)
    }

    @Test("attach(to: nil) — the marker left every window — leaves no recognizer attached anywhere")
    func attachToNilWindowLeavesNothingAttached() {
        let window = UIWindow()
        let coordinator = CrossBlockSelectionCancelCatcher.Coordinator(tracker: CrossBlockSelectionTracker())
        coordinator.attach(to: window)
        let previousRecognizer = coordinator.recognizer

        coordinator.attach(to: nil)

        #expect(!isAttached(previousRecognizer, to: window))
        #expect(coordinator.recognizer == nil)
        #expect(coordinator.attachedWindow == nil)
    }

    @Test("detach() removes the recognizer from its window and clears attachedWindow")
    func detachRemovesRecognizerFromWindow() {
        let window = UIWindow()
        let coordinator = CrossBlockSelectionCancelCatcher.Coordinator(tracker: CrossBlockSelectionTracker())
        coordinator.attach(to: window)
        let previousRecognizer = coordinator.recognizer

        coordinator.detach()

        #expect(!isAttached(previousRecognizer, to: window))
        #expect(coordinator.recognizer == nil)
        #expect(coordinator.attachedWindow == nil)
    }

    @Test("detach() with nothing attached is a harmless no-op")
    func detachWithNothingAttachedIsNoOp() {
        let coordinator = CrossBlockSelectionCancelCatcher.Coordinator(tracker: CrossBlockSelectionTracker())

        coordinator.detach()

        #expect(coordinator.attachedWindow == nil)
    }

    // swiftlint:disable:next line_length
    @Test("A marker view nested several levels deep under a UIWindow still resolves `.window` to that same window — the ancestor relationship `AnchorView.didMoveToWindow()` relies on")
    func deeplyNestedMarkerResolvesToTopWindow() {
        let window = UIWindow()
        let navBarContainer = UIView()
        let titleContainer = UIView()
        let marker = CrossBlockSelectionCancelCatcher.AnchorView()

        window.addSubview(navBarContainer)
        navBarContainer.addSubview(titleContainer)
        titleContainer.addSubview(marker)

        #expect(marker.window === window)
    }

    @Test("A marker view with no window anywhere above it resolves `.window` to nil")
    func unmountedMarkerHasNoWindow() {
        let container = UIView()
        let marker = CrossBlockSelectionCancelCatcher.AnchorView()
        container.addSubview(marker)

        #expect(marker.window == nil)
    }

    // swiftlint:disable:next line_length
    @Test("End-to-end wiring: adding a coordinator-linked marker to a window attaches the recognizer there; removing it detaches")
    func markerAndCoordinatorWireUpOnWindowChanges() {
        let window = UIWindow()
        let coordinator = CrossBlockSelectionCancelCatcher.Coordinator(tracker: CrossBlockSelectionTracker())
        let marker = CrossBlockSelectionCancelCatcher.AnchorView()
        marker.coordinator = coordinator

        window.addSubview(marker)
        #expect(isAttached(coordinator.recognizer, to: window))
        #expect(coordinator.attachedWindow === window)
        let attachedRecognizer = coordinator.recognizer

        marker.removeFromSuperview()
        #expect(!isAttached(attachedRecognizer, to: window))
        #expect(coordinator.recognizer == nil)
        #expect(coordinator.attachedWindow == nil)
    }

    // MARK: - Invariant 2, both directions together

    /// A small stand-in for `DetailScreen`'s own `focusedBlockId`
    /// (`@FocusState`, not something this unit-test target can construct
    /// or observe directly) plus `crossBlockSelectionTracker` — wired the
    /// exact same two ways `DetailScreen` wires the real ones:
    /// `CrossBlockSelectionOverlay.onSelectionBegan` clears focus the
    /// moment a drag starts, and `CrossBlockSelectionCancelCatcher
    /// .Coordinator.handleTap()` cancels the selection on any other tap.
    /// Proves the two callbacks' *shapes* keep both halves of invariant 2
    /// from ever being true at the same time, for every order the brief's
    /// scenarios can produce them in — the actual SwiftUI `@FocusState`
    /// bridging + UIKit gesture delivery those callbacks run inside of
    /// still needs manual/device verification, same carve-out as this
    /// file's other tests.
    @MainActor
    private final class EditingFocusStub {
        var focusedBlockId: String?
        let tracker = CrossBlockSelectionTracker()

        /// Mirrors `DetailScreen.crossBlockSelectionOverlay`'s
        /// `onSelectionBegan: { focusedBlockId = nil }` — called here
        /// instead of by a real gesture recognizer, the same "drive the
        /// callback directly" approach `CrossBlockSelectionDragTests`
        /// already uses for `beginSelection`/`extendSelection` themselves.
        func beginDragSelection(at location: DocumentTextLocation) {
            tracker.beginSelection(at: location)
            focusedBlockId = nil
        }

        /// Mirrors a block's own native tap-to-focus landing somewhere
        /// else, plus `crossBlockSelectionCancelCatcher`'s `handleTap()`
        /// firing for that same tap.
        func tapBlock(_ blockId: String) {
            CrossBlockSelectionCancelCatcher.Coordinator(tracker: tracker).handleTap()
            focusedBlockId = blockId
        }

        /// Mirrors a tap that lands on something other than a block (nav
        /// bar, title area, blank space) — only `crossBlockSelectionCancelCatcher`
        /// fires; nothing sets `focusedBlockId`, since nothing there is
        /// editable.
        func tapOutsideAnyBlock() {
            CrossBlockSelectionCancelCatcher.Coordinator(tracker: tracker).handleTap()
        }

        var bothModesActiveAtOnce: Bool {
            focusedBlockId != nil && tracker.isActive
        }
    }

    @Test("Invariant 2: starting a drag-selection while a block is focused clears that focus")
    func beginningSelectionClearsEditingFocus() {
        let stub = EditingFocusStub()
        stub.focusedBlockId = "a"

        stub.beginDragSelection(at: DocumentTextLocation(blockId: "a", offset: 2))

        #expect(stub.focusedBlockId == nil)
        #expect(stub.tracker.isActive == true)
        #expect(stub.bothModesActiveAtOnce == false)
    }

    // swiftlint:disable:next line_length
    @Test("Invariant 2: tapping a different block while a selection is active cancels the selection as focus moves (A6-a)")
    func tappingAnotherBlockCancelsSelectionAsFocusMoves() {
        let stub = EditingFocusStub()
        stub.focusedBlockId = "a"
        stub.beginDragSelection(at: DocumentTextLocation(blockId: "a", offset: 0))
        stub.tracker.extendSelection(to: DocumentTextLocation(blockId: "b", offset: 2))
        stub.tracker.endSelection()
        #expect(stub.tracker.isActive == true)
        #expect(stub.focusedBlockId == nil)

        stub.tapBlock("c")

        #expect(stub.tracker.isActive == false)
        #expect(stub.focusedBlockId == "c")
        #expect(stub.bothModesActiveAtOnce == false)
    }

    // swiftlint:disable:next line_length
    @Test("Invariant 2: tapping outside any block (nav bar, title area, blank space) cancels the selection without creating new focus (A6-b/c)")
    func tappingOutsideAnyBlockCancelsSelectionWithNoNewFocus() {
        let stub = EditingFocusStub()
        stub.beginDragSelection(at: DocumentTextLocation(blockId: "a", offset: 0))
        stub.tracker.extendSelection(to: DocumentTextLocation(blockId: "b", offset: 2))
        stub.tracker.endSelection()
        #expect(stub.tracker.isActive == true)

        stub.tapOutsideAnyBlock()

        #expect(stub.tracker.isActive == false)
        #expect(stub.focusedBlockId == nil)
        #expect(stub.bothModesActiveAtOnce == false)
    }

    // swiftlint:disable:next line_length
    @Test("Invariant 2: repeating begin-selection → cancel-by-tap → begin-selection again never lets both modes hold at once")
    func repeatedCycleNeverOverlapsBothModes() {
        let stub = EditingFocusStub()
        stub.focusedBlockId = "a"

        stub.beginDragSelection(at: DocumentTextLocation(blockId: "a", offset: 0))
        #expect(stub.bothModesActiveAtOnce == false)

        stub.tracker.extendSelection(to: DocumentTextLocation(blockId: "b", offset: 1))
        stub.tracker.endSelection()
        #expect(stub.bothModesActiveAtOnce == false)

        stub.tapBlock("b")
        #expect(stub.bothModesActiveAtOnce == false)

        stub.beginDragSelection(at: DocumentTextLocation(blockId: "b", offset: 0))
        #expect(stub.bothModesActiveAtOnce == false)
        // The drag's own finger has to lift (ending it) before a separate
        // tap-outside touch could even begin — matches `tapOutsideAnyBlock`'s
        // real-world precondition the same way `tapBlock`'s earlier call in
        // this test does.
        stub.tracker.endSelection()

        stub.tapOutsideAnyBlock()
        #expect(stub.bothModesActiveAtOnce == false)
        #expect(stub.tracker.isActive == false)
    }
}
