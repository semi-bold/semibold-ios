import SwiftUI
import UIKit

/// A screen-wide touch observer whose only job is canceling an active
/// cross-block selection the instant the user taps anything that isn't the
/// drag that's still creating it — `01-cross-block-selection-core` brief's
/// A6 ("선택 도중 다른 화면 요소를 탭함") and common invariant 2 ("편집
/// 모드와 선택 모드는 동시에 성립하지 않는다").
///
/// **One rule, no exceptions** (2026-10-02 decision folding A6-a's "다른
/// 블록을 탭" and A6-b/c's "그 외 화면 요소를 탭" into the same outcome):
/// every tap this type sees — on a different block, on the nav bar, on
/// blank space below the last block, anywhere within `DetailScreen`'s own
/// content window — ends the active selection the same way, via the same
/// `handleTap()`. There is no special case in here for any specific
/// control; this type doesn't know any of them exist, on purpose.
///
/// **Exception this type genuinely cannot cover — the keyboard toolbar's
/// "키보드 내리기" button.** `AccessoryToolbarCoordinator`'s toolbar is
/// `IndentableTextView.inputAccessoryView`, which iOS hosts in the system
/// keyboard's own `UIWindow`, not `DetailScreen`'s content window. This
/// type's recognizer is attached to the content window
/// (`Coordinator.attach(to:)`) specifically so it's a genuine UIKit
/// ancestor of everything hit-tested *in that window* — but a tap on the
/// dismiss button is hit-tested in a different window entirely, so no
/// window-anchored recognizer here can ever see it, regardless of how
/// this type is wired. The "no exception" rule for that one button is
/// instead enforced directly at its own tap handler
/// (`DetailScreen.configureAccessoryToolbar(forBlockId:)`'s
/// `onDismissKeyboard` closure calls `crossBlockSelectionTracker.cancel()`
/// explicitly) rather than by this type observing it, because observing
/// it from here is not architecturally possible. A6-a's other half — the tapped block also
/// becoming the new typing-focus location, caret placed where the finger
/// landed — needs no code here at all: that's plain native `UITextView`
/// tap-to-focus, already happening underneath this view, completely
/// independent of this type's own `cancel()` call (see `DetailScreen
/// .crossBlockSelectionCancelCatcher`'s doc comment for how the two
/// combine into A6-a without either one needing to know about the other).
///
/// **Deliberately separate from `CrossBlockSelectionOverlay`, not an
/// extension of it.** That overlay's own `UILongPressGestureRecognizer`
/// resolves every touch point against `BlockTextViewRegistry`'s mounted
/// blocks, falling back to "whichever mounted block is nearest" for a
/// point that isn't over any block at all
/// (`CrossBlockSelectionHitTester.location(forPoint:in:candidates:)`'s doc
/// comment) — a reasonable fallback for a drag that's still somewhere over
/// the block list, but exactly the wrong behavior at this type's much wider
/// reach (`DetailScreen`'s whole screen, nav bar and title area included):
/// a long press sitting on the back button for 0.5s has no business
/// anchoring a selection at "whichever block happens to be nearest." Using
/// a plain `UITapGestureRecognizer` here — no hit-testing against blocks at
/// all, just "did a tap happen" — sidesteps that risk entirely instead of
/// widening the drag-select overlay's own reach to cover the whole screen.
///
/// ## How this actually guarantees seeing every tap in `DetailScreen`
///
/// Two earlier attempts at this got the attachment point wrong:
///
/// 1. Mounting this type's `UIView` via SwiftUI's `.background()` on
///    `DetailScreen`'s outer `VStack` — risked SwiftUI composing that
///    branch as a UIKit *sibling* of the block list's own backing views
///    rather than an ancestor of them, in which case the tap recognizer
///    attached to it would never see a touch that hit-tests to the block
///    list at all.
/// 2. "Fixing" that by switching to `.overlay{}` instead — `.overlay{}`
///    and `.background{}` both compose their content as SwiftUI
///    `ZStack`-style layers; they differ only in *paint order* (in front
///    vs. behind), not in producing any ancestor/descendant relationship
///    in the resulting UIKit view tree. Making this view paint in front,
///    covering the whole screen, risked making it the *sole* UIKit
///    `hitTest(_:with:)` winner for every touch in that region — which
///    would have made it intercept the nav bar's back/menu buttons and
///    every block's own tap-to-focus, not merely observe alongside them.
///
/// Documented UIKit touch delivery doesn't care about SwiftUI paint order
/// at all: a gesture recognizer attached to a view `X` receives a touch
/// whenever that touch's hit-tested view is `X` itself **or any view that
/// has `X` somewhere in its own `superview` ancestor chain** — "a gesture
/// recognizer attached to a parent view receives touches that hit-test to
/// any of its child subviews," regardless of how that parent is drawn
/// relative to its children. The one UIKit-guaranteed ancestor of
/// *literally every view* hit-tested while `DetailScreen` is on screen is
/// the `UIWindow` hosting it — `UIWindow` is itself a `UIView` subclass and
/// can host gesture recognizers exactly like any other view. So this type
/// doesn't hit-test or hang a touch surface over any particular region at
/// all anymore: `AnchorView` is a zero-size, invisible marker mounted
/// somewhere stable in `DetailScreen`'s hierarchy purely so its `UIView
/// .window` lifecycle hook (`didMoveToWindow()`) fires; `Coordinator
/// .attach(to:)` then moves the actual `UITapGestureRecognizer` onto that
/// window itself. Because `attach(to:)` runs again every time the marker's
/// `window` changes, the recognizer is only ever live while some instance
/// of this view is actually mounted in that window's hierarchy — i.e.
/// while `DetailScreen` is genuinely on screen in it, the same scoping a
/// visible overlay would have given for free, without needing this view to
/// occupy any bounds or paint order to get it.
///
/// Uses the same `cancelsTouchesInView = false` + always-simultaneous
/// delegate recipe `CrossBlockSelectionOverlay` already relies on to
/// coexist with every native tap/long-press underneath it (the back
/// button, the menu button, every block's text view, and — just as
/// important once this is attached screen-wide to the window — any
/// system-level gesture also live in that window, e.g. the navigation
/// stack's edge-swipe-to-go-back pan) — see that type's doc comment for
/// why that combination lets this view *observe* every touch without
/// taking it away from whatever would otherwise handle it. A plain tap
/// recognizer and a pan-based back-swipe recognizer don't compete for the
/// same touch to begin with (different recognition rules entirely), so the
/// always-simultaneous delegate here is a belt-and-suspenders guarantee,
/// not the only thing standing between this type and breaking that system
/// gesture.
struct CrossBlockSelectionCancelCatcher: UIViewRepresentable {
    var tracker: CrossBlockSelectionTracker

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.tracker = tracker
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tracker: tracker)
    }

    /// Torn down whenever SwiftUI removes this representable from the view
    /// tree outright (as opposed to just reusing the same `AnchorView`
    /// across an `updateUIView` cycle) — `AnchorView.didMoveToWindow()`
    /// already detaches the recognizer the moment `removeFromSuperview()`
    /// clears its `window`, so this is a defensive backstop for any SwiftUI
    /// lifecycle path that tears the view down without going through that,
    /// not the primary mechanism.
    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// A zero-size, non-interactive marker view — it never hit-tests
    /// anything and never needs to occupy any particular bounds or paint
    /// order (see this type's doc comment for why). Its only job is
    /// existing somewhere in `DetailScreen`'s view hierarchy so
    /// `didMoveToWindow()` fires once that hierarchy is actually mounted
    /// into a `UIWindow`, at which point `coordinator` moves the real
    /// gesture recognizer onto that window.
    final class AnchorView: UIView {
        weak var coordinator: Coordinator?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isHidden = true
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Fires whenever this view's own `window` changes — to a real
        /// window once SwiftUI mounts `DetailScreen` into one, back to
        /// `nil` if this screen is popped/covered and its views come out of
        /// the window, and to a (potentially different) window again if
        /// it's remounted. `coordinator.attach(to:)` re-targets the
        /// recognizer every time, so it's only ever live while this view is
        /// actually part of a mounted window's hierarchy.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var tracker: CrossBlockSelectionTracker

        /// The window the live recognizer is currently attached to, if any
        /// — `nil` whenever `AnchorView` isn't currently mounted in a
        /// window (not yet added to the hierarchy, or popped/covered).
        private(set) weak var attachedWindow: UIWindow?

        /// The coordinator's own live recognizer instance, if any — kept
        /// at `internal` (not `private`) access so tests can confirm *this
        /// specific* recognizer's presence/absence on a window by identity
        /// rather than by counting `window.gestureRecognizers`, which can
        /// already carry other `UITapGestureRecognizer`s the system itself
        /// attaches to a `UIWindow` independently of anything this type
        /// does.
        private(set) var recognizer: UITapGestureRecognizer?

        init(tracker: CrossBlockSelectionTracker) {
            self.tracker = tracker
        }

        /// Moves the tap recognizer onto `window`, detaching it from
        /// wherever it was before. Safe to call repeatedly with the same
        /// window (e.g. if `didMoveToWindow()` ever fired more than once
        /// for the same window) — it always detaches first, so there's
        /// never more than one live recognizer from this coordinator at a
        /// time, regardless of how many times this runs. Passing `nil`
        /// (the window this view just left) leaves the recognizer fully
        /// detached until the next real window shows up.
        func attach(to window: UIWindow?) {
            detach()
            guard let window else { return }
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
            attachedWindow = window
        }

        /// Removes the recognizer from whatever window it's currently on,
        /// if any — called both by `attach(to:)` before re-targeting and by
        /// `dismantleUIView`/`didMoveToWindow(nil)` when this view leaves
        /// the hierarchy for good.
        func detach() {
            if let recognizer, let attachedWindow {
                attachedWindow.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            attachedWindow = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Always `true` — this recognizer only ever observes a touch
            // alongside whatever native control (button, text view),
            // system gesture (edge-swipe-to-go-back), or the drag-select
            // overlay's own recognizer would otherwise handle it; it never
            // competes for exclusive ownership.
            true
        }

        /// A plain `UITapGestureRecognizer` only recognizes a quick,
        /// (near-)stationary touch — a touch that moves far enough to
        /// become a drag-selection (A2/A3) fails this recognizer well
        /// before the finger lifts, so `handleTap()` is never called for
        /// the same touch that's busy *creating* the selection it would
        /// otherwise cancel out from under itself. `!tracker.isDragging`
        /// below is an extra belt-and-suspenders guard for that same case —
        /// kept because it costs nothing and makes the intent explicit,
        /// even though it shouldn't be reachable in practice.
        @objc func handleTap() {
            guard tracker.isActive, !tracker.isDragging else { return }
            tracker.cancel()
        }
    }
}
