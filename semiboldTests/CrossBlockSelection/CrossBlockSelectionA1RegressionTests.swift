import Testing
import UIKit

@testable import semibold

/// Regression guard for scenario A1 in `CrossBlockSelection/README.md` —
/// long-pressing in the middle of a block's text (no drag yet) should
/// still place an empty caret, the same as iOS's native `UITextView`
/// behavior, and must NOT jump straight to a word-level selection. This
/// brief (`.claude/features/01-cross-block-selection-core.md`) replaces
/// *drag*-selection with a custom cross-block overlay (A2 onward) but
/// deliberately leaves caret placement itself untouched — "타이핑을 위한
/// 캐럿 배치... 는 이 범위에 포함되지 않는다" (brief Scope;
/// `tasks/NO-010.md` §4 "적용 범위 확장" says the same). A1 itself has
/// nothing to implement — this file exists purely as a safety net, since
/// upcoming AC items in this same brief add gesture recognizers near this
/// exact `ParagraphTextField`/`IndentableTextView` code path for the new
/// drag-selection overlay, and could accidentally intercept or disable
/// the native long-press-to-caret path if not careful.
///
/// **Why this doesn't simulate an actual long-press touch.** A real
/// long-press is delivered through `UIApplication`'s touch event pipeline
/// onto a view hosted in a live window with a running gesture-recognizer
/// state machine. This repo's `project.yml` only defines `semiboldTests`
/// (a `bundle.unit-test` target) — there is no XCUITest target, and
/// driving a synthetic hardware touch sequence through a Swift Testing
/// unit test isn't practical (the same limitation `IndentableTextViewTests`
/// already documents for hardware key events, for the same underlying
/// reason: no hosted window/responder chain to deliver the event through).
/// So instead of simulating the gesture itself, these tests lock in the
/// *preconditions* iOS's native long-press-to-caret behavior depends on,
/// configured exactly as `ParagraphTextField.makeUIView` sets them up
/// today. If a later change (e.g. wiring up the A2/A3 drag-selection
/// overlay) flips any of these — disables native selection, or attaches
/// an extra gesture recognizer that beats UIKit's own long-press handling
/// to the touch — one of these tests fails and flags it for a human to
/// look at before it ships, rather than silently regressing A1.
@MainActor
struct CrossBlockSelectionA1RegressionTests {
    /// Builds an `IndentableTextView` configured the same way
    /// `ParagraphTextField.makeUIView` configures every block's text view
    /// today, with non-empty text and no existing selection — the exact
    /// setup A1 describes ("블록 하나의 텍스트 중간").
    private func makeBlockTextView(text: String = "Hello world") -> IndentableTextView {
        let textView = IndentableTextView()
        textView.text = text
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    @Test("A block's text view is both selectable and editable — required for a native long-press to place a caret at all")
    func blockTextViewIsSelectableAndEditable() {
        let textView = makeBlockTextView()

        #expect(textView.isSelectable == true)
        #expect(textView.isEditable == true)
    }

    @Test("IndentableTextView installs no extra gesture recognizers beyond plain UITextView's own — nothing intercepts the native long-press-to-caret gesture before UIKit sees it")
    func indentableTextViewAddsNoExtraGestureRecognizers() {
        let plainTextView = UITextView()
        plainTextView.text = "Hello world"

        let blockTextView = makeBlockTextView()

        // Comparing by recognizer class name (not instance/count order) —
        // what matters for this guard is that our subclass's set of
        // recognizer *types* matches a stock `UITextView`'s exactly, i.e.
        // nothing has been added, removed, or replaced on top of it.
        let plainRecognizerTypes = (plainTextView.gestureRecognizers ?? [])
            .map { String(describing: type(of: $0)) }
            .sorted()
        let blockRecognizerTypes = (blockTextView.gestureRecognizers ?? [])
            .map { String(describing: type(of: $0)) }
            .sorted()

        #expect(!plainRecognizerTypes.isEmpty) // sanity check the comparison below is non-vacuous
        #expect(blockRecognizerTypes == plainRecognizerTypes)
    }
}
