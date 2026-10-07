import SwiftUI
import UIKit

/// A transparent, screen-wide touch observer whose only job is canceling an
/// active cross-block selection the instant the user taps anything that
/// isn't the drag that's still creating it — `01-cross-block-selection-core`
/// brief's A6 ("선택 도중 다른 화면 요소를 탭함") and common invariant 2
/// ("편집 모드와 선택 모드는 동시에 성립하지 않는다").
///
/// **One rule, no exceptions** (2026-10-02 decision folding A6-a's "다른
/// 블록을 탭" and A6-b/c's "그 외 화면 요소를 탭" into the same outcome):
/// every tap this view sees — on a different block, on the nav bar, on
/// blank space below the last block, anywhere within `DetailScreen` — ends
/// the active selection the same way, via the same `handleTap()`. There is
/// no special case in here for the keyboard toolbar's "키보드 내리기"
/// button or any other specific control; this type doesn't know any of
/// them exist, on purpose. A6-a's other half — the tapped block also
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
/// Uses the same `cancelsTouchesInView = false` + always-simultaneous
/// delegate recipe `CrossBlockSelectionOverlay` already relies on to
/// coexist with every native tap/long-press underneath it (the back
/// button, the menu button, every block's text view) — see that type's doc
/// comment for why that combination lets this view *observe* every touch
/// without taking it away from whatever would otherwise handle it.
struct CrossBlockSelectionCancelCatcher: UIViewRepresentable {
    var tracker: CrossBlockSelectionTracker

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let recognizer = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleTap)
        )
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.tracker = tracker
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tracker: tracker)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var tracker: CrossBlockSelectionTracker

        init(tracker: CrossBlockSelectionTracker) {
            self.tracker = tracker
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Always `true` — this recognizer only ever observes a touch
            // alongside whatever native control (button, text view) or the
            // drag-select overlay's own recognizer would otherwise handle
            // it; it never competes for exclusive ownership.
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
