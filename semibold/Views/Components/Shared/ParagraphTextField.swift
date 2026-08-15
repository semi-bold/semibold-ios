import SwiftUI
import UIKit

/// A growing, multi-line text input for a single paragraph block.
///
/// SwiftUI's `TextField`/`TextEditor` don't expose the cursor position or
/// let Return be intercepted before it inserts a newline, both of which
/// `Planning_4_BlockCreateFlow`'s Enter-to-create behavior needs
/// (PLANNING §5.4, §13.1: "Enter → 현재 블록 뒤에 새 paragraph block
/// 생성"). This wraps a `UITextView` to provide that, while still
/// reporting plain text back to SwiftUI via a binding.
struct ParagraphTextField: UIViewRepresentable {
    @Binding var text: String

    /// The typography this block's text is shown in — `AppTheme.Typography
    /// .body` for a plain paragraph, or `.heading1`/`.heading2`/`.heading3`
    /// for a `.heading` block (§7.1/§7.3's `# `/`## `/`### ` conversions).
    /// Defaults to `.body` so existing call sites don't need to change.
    var textStyle: TextStyleToken = AppTheme.Typography.body

    /// The text color this block's content is shown in —
    /// `AppTheme.Colors.Content.primary` for most blocks, or `.text2` for a
    /// `.blockquote` block's dimmed quote text (§7.1/§7.3's `> quote`
    /// syntax). Defaults to `.text1` so existing call sites don't need to
    /// change.
    var textColor: Color = AppTheme.Colors.Content.primary

    /// Whether this block's text is shown in a monospaced font — `true`
    /// for a `.codeBlock` block's code (§7.1/§7.3's ` ```lang ` syntax), so
    /// code reads distinctly from prose. Defaults to `false` so existing
    /// call sites don't need to change.
    var isMonospaced: Bool = false

    /// Called as the user edits this block's text, so the document
    /// editor can save the change.
    var onTextChange: (String) -> Void

    /// Called when the user presses Return, with the cursor's character
    /// offset into `text` at the time of the press — everything after
    /// that offset moves into the new block created right below this one.
    var onEnter: (_ cursorOffset: Int) -> Void

    /// Called when the user presses Backspace with the cursor at the very
    /// start of this block's text (offset 0), so the editor can merge this
    /// block into the previous one or delete it
    /// (`Planning_4_BlockCreateFlow`, PLANNING §13.1 "Backspace at empty
    /// block: 이전 블록과 병합 또는 현재 블록 삭제").
    var onBackspaceAtStart: () -> Void

    /// Called on a hardware Tab press (`tasks/NO-009.md` §2.1/§3.3), so a
    /// focused list item can nest one level under its previous sibling.
    /// `nil` for every non-list block — see `IndentableTextView.keyCommands`
    /// for why leaving this `nil` also leaves Tab's default behavior
    /// (inserting a tab character) untouched.
    var onIndent: (() -> Void)? = nil

    /// Called on a hardware Shift+Tab press (`tasks/NO-009.md` §2.1/§3.3),
    /// so a focused nested list item can be promoted back under its
    /// grandparent. `nil` for every non-list block, same as `onIndent`.
    var onOutdent: (() -> Void)? = nil

    /// Whether the on-screen keyboard toolbar's outdent button should be
    /// enabled — `false` when the focused list item has no parent
    /// (already top-level), in which case the button shows at ~35%
    /// opacity and doesn't call `onOutdent`
    /// (`05-onscreen-keyboard-indent-toolbar` brief's Decisions — mirrors
    /// `outdentBlock`'s own no-op guard, but surfaced as a visibly-inert
    /// control rather than a silent no-op tap). Ignored when `onOutdent`
    /// is `nil` (no toolbar to show it in). Defaults to `true` so existing
    /// call sites don't need to change.
    var canOutdent: Bool = true

    /// Called when the on-screen keyboard toolbar's dismiss button is
    /// tapped (`05-onscreen-keyboard-indent-toolbar` brief) — routes back
    /// to `DetailViewModel`'s existing `blockIdToDefocus` focus-clearing
    /// signal rather than a direct UIKit `resignFirstResponder`/
    /// `endEditing` call, keeping `@FocusState` the single source of
    /// truth for focus. `nil` for every non-list block, same as
    /// `onIndent`/`onOutdent`.
    var onDismissKeyboard: (() -> Void)? = nil

    /// A one-shot character offset to move the caret to once this block
    /// becomes focused, e.g. the merge point when a Backspace-at-start
    /// merges the block below into this one. `DetailScreen` clears this back
    /// to `nil` once it's been applied.
    @Binding var cursorOffsetToApply: Int?

    /// The `UIFont` for this field's current `textStyle`/`isMonospaced` —
    /// a monospaced font for `.codeBlock` blocks, or the system font at
    /// `textStyle`'s size/weight otherwise.
    private var font: UIFont {
        if isMonospaced {
            return UIFont.monospacedSystemFont(ofSize: textStyle.size, weight: textStyle.weight.uiFontWeight)
        }
        return UIFont.systemFont(ofSize: textStyle.size, weight: textStyle.weight.uiFontWeight)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = IndentableTextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.backgroundColor = .clear
        textView.textColor = UIColor(textColor)
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.text = text
        textView.onIndent = onIndent
        textView.onOutdent = onOutdent
        textView.canOutdent = canOutdent
        textView.onDismissKeyboard = onDismissKeyboard
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // `Coordinator.parent` is only set once, in `makeCoordinator()` —
        // refresh it on every update so `onEnter`/`onBackspaceAtStart`
        // (which close over this call's `text`/`content`, not a value
        // handed to them at call time the way `onTextChange`'s `String`
        // argument is) run against this render's callbacks and captured
        // state instead of whatever was current the first time this row
        // appeared. Without this, a stale capture of e.g. `content
        // .plainText` from that first (often-empty) render would silently
        // stand in for the text actually on screen.
        context.coordinator.parent = self

        // Same rationale as `context.coordinator.parent` above — refresh
        // these on every update so a hardware Tab/Shift+Tab press always
        // calls this render's `onIndent`/`onOutdent` (closing over the
        // right block id) rather than whatever closure happened to be
        // current the first time this row appeared.
        if let indentableTextView = uiView as? IndentableTextView {
            indentableTextView.onIndent = onIndent
            indentableTextView.onOutdent = onOutdent
            indentableTextView.canOutdent = canOutdent
            indentableTextView.onDismissKeyboard = onDismissKeyboard
        }

        if uiView.text != text {
            uiView.text = text
        }

        let font = font
        if uiView.font != font {
            uiView.font = font
        }

        let color = UIColor(textColor)
        if uiView.textColor != color {
            uiView.textColor = color
        }

        if let offset = cursorOffsetToApply {
            let clamped = min(max(offset, 0), uiView.text.utf16.count)
            uiView.selectedRange = NSRange(location: clamped, length: 0)
            DispatchQueue.main.async {
                cursorOffsetToApply = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Without this override, SwiftUI falls back to `UITextView`'s own
    /// sizing, which — since `isScrollEnabled = false` gives it no fixed
    /// width to wrap against — hugs the width of its *text content*
    /// instead of filling `proposal.width` (the row's full width, per the
    /// call sites' `.frame(maxWidth: .infinity)`). The row's background
    /// still visually spans the full width regardless (that's painted by
    /// an ancestor view), but the `UITextView`'s actual bounds — and so
    /// its tappable area — end up only as wide as the text, leaving
    /// everything past it in the row untappable. Explicitly returning the
    /// proposed width (falling back to the view's current width if none
    /// is proposed) fixes that, while height still comes from the text
    /// content, preserving the auto-growing multi-line behavior.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: height)
    }

    /// Forwards `UITextView` editing events back to SwiftUI, and turns a
    /// plain Return keypress into "create a new block here" instead of
    /// letting it insert a newline.
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ParagraphTextField

        init(_ parent: ParagraphTextField) {
            self.parent = parent
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if text.isEmpty && range.location == 0 && range.length == 0 {
                // Backspace pressed with the caret at the very start of the
                // block's text — let the editor decide whether to merge
                // this block into the previous one or delete it.
                parent.onBackspaceAtStart()
                return false
            }

            guard text == "\n" else { return true }

            let cursorOffset = range.location
            parent.onEnter(cursorOffset)
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.onTextChange(textView.text)
        }
    }
}

/// A `UITextView` subclass that turns a hardware Tab/Shift+Tab press into
/// `onIndent`/`onOutdent`, rather than the character `UITextViewDelegate
/// .shouldChangeTextIn` sees on every other keypress, and shows an
/// on-screen keyboard toolbar for the on-screen keyboard, which has no
/// physical Tab key at all (`05-onscreen-keyboard-indent-toolbar` brief,
/// `tasks/NO-009.md` §3.3).
///
/// `shouldChangeTextIn` (used for Enter/Backspace above) only fires when a
/// keypress actually changes the text — Shift+Tab typically inserts no
/// character at all, so it never reaches that delegate method
/// (`tasks/NO-009.md` §3.3). `UIKeyCommand`s registered via this
/// `UIResponder` override, by contrast, are consulted directly against a
/// hardware key event before any text insertion happens, so they can catch
/// Tab and Shift+Tab regardless of whether either would otherwise insert a
/// character.
///
/// `keyCommands` only advertises the Tab/Shift+Tab commands while the
/// matching `onIndent`/`onOutdent` closure is non-`nil` — when both are
/// `nil` (every non-list block), this returns `nil` and Tab falls through
/// to `UITextView`'s own default handling (inserting a tab character),
/// unchanged from before this type existed.
///
/// The on-screen toolbar is owned by `AccessoryToolbarCoordinator.shared`,
/// **one instance shared across every block in the document**, not built
/// per `IndentableTextView` — a document with N blocks only ever has one
/// actual first responder at a time, so N separately-constructed
/// `UIToolbar`s (each with their own `UIButton`s and SF Symbol image
/// loads) was pure waste, and — when this row's `onIndent`/`onOutdent`/
/// `onDismissKeyboard` got reassigned on every SwiftUI re-render, for
/// every row, regardless of focus — measurable main-thread cost on every
/// keystroke and on the document's very first appearance. `configure(for:)`
/// only runs when a block actually gains focus (`becomeFirstResponder`
/// below) or when the *currently-focused* block's own indent/outdent
/// state changes — never for the other N-1 unfocused rows.
final class IndentableTextView: UITextView {
    var onIndent: (() -> Void)? {
        didSet { refreshSharedToolbarIfActive(reloadAccessoryView: true) }
    }
    var onOutdent: (() -> Void)? {
        didSet { refreshSharedToolbarIfActive(reloadAccessoryView: false) }
    }

    /// Whether the on-screen toolbar's outdent button is enabled — see
    /// `ParagraphTextField.canOutdent`'s doc comment. Defaults to `true` so
    /// a block that never sets this explicitly (every non-list block, and
    /// list items before `updateUIView`'s first pass) doesn't start out
    /// dimmed.
    var canOutdent: Bool = true {
        didSet { refreshSharedToolbarIfActive(reloadAccessoryView: false) }
    }

    /// Called when the on-screen toolbar's dismiss button is tapped — see
    /// `ParagraphTextField.onDismissKeyboard`'s doc comment. Every block
    /// kind sets this (not just list kinds — unlike `onIndent`/
    /// `onOutdent`), so it's what `inputAccessoryView` gates on: every
    /// block gets at least a dismiss-only toolbar.
    var onDismissKeyboard: (() -> Void)? {
        didSet { refreshSharedToolbarIfActive(reloadAccessoryView: true) }
    }

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []
        if onIndent != nil {
            commands.append(
                UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleIndentKeyCommand))
            )
        }
        if onOutdent != nil {
            commands.append(
                UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(handleOutdentKeyCommand))
            )
        }
        return commands.isEmpty ? nil : commands
    }

    /// Shows the shared toolbar above the on-screen keyboard whenever
    /// `onDismissKeyboard` is non-`nil` — every block kind sets this, so
    /// every block gets at least the keyboard-dismiss button.
    /// `AccessoryToolbarCoordinator.configure(for:)` is what keeps the
    /// toolbar's *content* list-aware (indent/outdent shown only while
    /// `onIndent`/`onOutdent` are non-`nil`, the same check `keyCommands`
    /// uses) — this getter only decides whether a toolbar shows at all.
    ///
    /// `UITextView.inputAccessoryView` is read-write (`{ get set }`) on
    /// `UIResponder`, so overriding it needs a `set` too, even though
    /// nothing outside this type ever assigns it — this view's accessory
    /// view is entirely derived from `onDismissKeyboard`, not settable
    /// from outside.
    override var inputAccessoryView: UIView? {
        get { onDismissKeyboard != nil ? AccessoryToolbarCoordinator.shared.toolbar : nil }
        set { /* Derived from `onDismissKeyboard` — intentionally ignored. */ }
    }

    /// The point where a block's toolbar actually becomes relevant:
    /// gaining keyboard focus. Re-targets the shared toolbar at `self` so
    /// its buttons act on *this* block, and refreshes its content/state
    /// for this block's `onIndent`/`onOutdent`/`canOutdent`.
    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            AccessoryToolbarCoordinator.shared.configure(for: self)
        }
        return didBecomeFirstResponder
    }

    /// The `UIKeyCommand` target-action for a plain Tab press — a thin
    /// `@objc` forwarder to `onIndent` so tests can also call it directly,
    /// the same way a real Tab press would, without needing to simulate an
    /// actual hardware key event.
    @objc func handleIndentKeyCommand() {
        onIndent?()
    }

    /// The `UIKeyCommand` target-action for a Shift+Tab press — see
    /// `handleIndentKeyCommand`.
    @objc func handleOutdentKeyCommand() {
        onOutdent?()
    }

    /// Refreshes the shared toolbar's content/state and, when
    /// `reloadAccessoryView` is `true`, forces UIKit to re-query
    /// `inputAccessoryView` right away — but only while `self` is the
    /// block currently focused. `onIndent`/`onOutdent`/`onDismissKeyboard`/
    /// `canOutdent` are reassigned on every SwiftUI re-render for *every*
    /// row (`ParagraphTextField.updateUIView`), so without the
    /// `isFirstResponder` guard this would redo the same work this type
    /// exists to avoid — see this type's doc comment. For the other N-1
    /// unfocused rows, this is a cheap early return.
    ///
    /// `reloadAccessoryView` only needs to be `true` for `onIndent`/
    /// `onDismissKeyboard` — those can flip a block between "no toolbar"/
    /// "toolbar" or "dismiss-only"/"indent+outdent+dismiss" while already
    /// focused (e.g. `DetailViewModel.exitEmptyListItem` converting a
    /// focused empty list item to a paragraph in place), which needs
    /// `reloadInputViews()` to actually show up. `onOutdent`/`canOutdent`
    /// only ever change the *already-shown* toolbar's button state, which
    /// `configure(for:)` updates in place without needing a reload.
    private func refreshSharedToolbarIfActive(reloadAccessoryView: Bool) {
        guard isFirstResponder else { return }
        AccessoryToolbarCoordinator.shared.configure(for: self)
        if reloadAccessoryView {
            reloadInputViews()
        }
    }
}

/// Coordinates the single keyboard accessory toolbar shared by every
/// `IndentableTextView` in the app — see that type's doc comment for why
/// one shared instance replaces one-per-block construction. Only the
/// block currently focused ever has its `inputAccessoryView` actually
/// queried/displayed by UIKit, so re-pointing one toolbar at whichever
/// block just gained focus is both correct and far cheaper than building
/// a toolbar per block.
final class AccessoryToolbarCoordinator: NSObject {
    static let shared = AccessoryToolbarCoordinator()

    private override init() {}

    /// The block whose `onIndent`/`onOutdent`/`onDismissKeyboard` the
    /// toolbar's buttons currently act on — weak since this coordinator
    /// outlives any single block's text view (e.g. once scrolled
    /// off-screen and reused by `List`).
    private(set) weak var activeTextView: IndentableTextView?

    lazy var toolbar: UIToolbar = {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        toolbar.autoresizingMask = [.flexibleWidth]
        toolbar.isTranslucent = false
        toolbar.barTintColor = UIColor(AppTheme.Colors.Neutral.n800)
        toolbar.sizeToFit()
        return toolbar
    }()

    lazy var indentButton = makeButton(systemName: "increase.indent", action: #selector(handleIndentTap))
    lazy var outdentButton = makeButton(systemName: "decrease.indent", action: #selector(handleOutdentTap))
    lazy var dismissButton = makeButton(systemName: "keyboard", action: #selector(handleDismissTap))

    private func makeButton(systemName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = UIColor(AppTheme.Colors.Content.secondary)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    /// Re-targets the shared toolbar at `textView` — its content
    /// (indent/outdent shown only while `textView.onIndent` is non-`nil`,
    /// the same check `IndentableTextView.keyCommands` uses, so both
    /// agree on "is this a list-kind block") and outdent's enabled/~35%-
    /// dimmed state (`05-onscreen-keyboard-indent-toolbar` brief's
    /// Decisions). Called only when a block gains focus
    /// (`IndentableTextView.becomeFirstResponder()`) or when the
    /// currently-focused block's own state changes
    /// (`refreshSharedToolbarIfActive`) — never once per unfocused row.
    func configure(for textView: IndentableTextView) {
        activeTextView = textView
        if textView.onIndent != nil {
            toolbar.items = [
                UIBarButtonItem(customView: indentButton),
                UIBarButtonItem(customView: outdentButton),
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(customView: dismissButton)
            ]
        } else {
            toolbar.items = [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(customView: dismissButton)
            ]
        }
        outdentButton.isEnabled = textView.canOutdent
        outdentButton.alpha = textView.canOutdent ? 1.0 : 0.35
    }

    /// The toolbar's indent button tap — always calls `activeTextView`'s
    /// `onIndent` unconditionally, matching indent's own lack of a
    /// "can't act" state (unlike outdent, indent has nothing to disable:
    /// any list item can nest under its previous sibling).
    @objc private func handleIndentTap() {
        activeTextView?.onIndent?()
    }

    /// The toolbar's outdent button tap — only calls `onOutdent` while
    /// `activeTextView.canOutdent` is `true`, so a top-level item's
    /// dimmed outdent button stays inert even if it somehow still
    /// receives a tap (belt and suspenders alongside `configure(for:)`
    /// disabling the button itself).
    @objc private func handleOutdentTap() {
        guard let activeTextView, activeTextView.canOutdent else { return }
        activeTextView.onOutdent?()
    }

    /// The toolbar's keyboard-dismiss button tap.
    @objc private func handleDismissTap() {
        activeTextView?.onDismissKeyboard?()
    }
}

private extension Font.Weight {
    /// Maps a SwiftUI font weight to its `UIFont.Weight` equivalent, so
    /// `ParagraphTextField`'s `UITextView` can match an `AppTheme`
    /// typography token's weight exactly.
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
