import Testing
import UIKit

@testable import semibold

/// Tests for `IndentableTextView` and `AccessoryToolbarCoordinator`
/// (`Views/Components/Shared/ParagraphTextField.swift`) — the `UITextView`
/// subclass that turns a hardware Tab/Shift+Tab press into
/// `onIndent`/`onOutdent` (`tasks/NO-009.md` §2.1/§3.3), and the single
/// keyboard accessory toolbar shared across every block instead of one
/// built per block.
///
/// Simulating an actual hardware key event, or a real `becomeFirstResponder()`
/// (which needs a live window to succeed), isn't practical in this test
/// target — so these instead check the things that make both correct
/// without either:
/// - `keyCommands` only advertises Tab/Shift+Tab when a handler is set, so
///   a block with no handler falls straight through to `UITextView`'s own
///   default Tab behavior (inserting a tab character) rather than being
///   silently swallowed.
/// - The `@objc` target-action methods those `UIKeyCommand`s point at
///   forward to `onIndent`/`onOutdent` when called directly — the same
///   call UIKit itself makes once it resolves a real Tab/Shift+Tab press
///   against `keyCommands`.
/// - `AccessoryToolbarCoordinator.configure(for:)` — what
///   `becomeFirstResponder()` calls in production — called directly to
///   simulate "this block just gained focus."
@MainActor
struct IndentableTextViewTests {
    @Test("keyCommands is nil when neither onIndent nor onOutdent is set — Tab keeps its default behavior")
    func keyCommandsIsNilWithNoHandlers() {
        let textView = IndentableTextView()

        #expect(textView.keyCommands == nil)
    }

    @Test("keyCommands advertises only a plain-Tab command when onIndent is set but onOutdent isn't")
    func keyCommandsAdvertisesOnlyTabWhenOnlyOnIndentSet() throws {
        let textView = IndentableTextView()
        textView.onIndent = {}

        let commands = try #require(textView.keyCommands)

        #expect(commands.count == 1)
        #expect(commands[0].input == "\t")
        #expect(commands[0].modifierFlags == [])
    }

    @Test("keyCommands advertises only a Shift+Tab command when onOutdent is set but onIndent isn't")
    func keyCommandsAdvertisesOnlyShiftTabWhenOnlyOnOutdentSet() throws {
        let textView = IndentableTextView()
        textView.onOutdent = {}

        let commands = try #require(textView.keyCommands)

        #expect(commands.count == 1)
        #expect(commands[0].input == "\t")
        #expect(commands[0].modifierFlags == .shift)
    }

    @Test("keyCommands advertises both Tab and Shift+Tab when both handlers are set")
    func keyCommandsAdvertisesBothWhenBothHandlersSet() throws {
        let textView = IndentableTextView()
        textView.onIndent = {}
        textView.onOutdent = {}

        let commands = try #require(textView.keyCommands)

        #expect(commands.count == 2)
        #expect(commands.contains { $0.input == "\t" && $0.modifierFlags == [] })
        #expect(commands.contains { $0.input == "\t" && $0.modifierFlags == .shift })
    }

    @Test("The plain-Tab key command's target-action calls onIndent, not onOutdent")
    func handleIndentKeyCommandCallsOnlyOnIndent() {
        let textView = IndentableTextView()
        var indentCallCount = 0
        var outdentCallCount = 0
        textView.onIndent = { indentCallCount += 1 }
        textView.onOutdent = { outdentCallCount += 1 }

        textView.handleIndentKeyCommand()

        #expect(indentCallCount == 1)
        #expect(outdentCallCount == 0)
    }

    @Test("The Shift+Tab key command's target-action calls onOutdent, not onIndent")
    func handleOutdentKeyCommandCallsOnlyOnOutdent() {
        let textView = IndentableTextView()
        var indentCallCount = 0
        var outdentCallCount = 0
        textView.onIndent = { indentCallCount += 1 }
        textView.onOutdent = { outdentCallCount += 1 }

        textView.handleOutdentKeyCommand()

        #expect(indentCallCount == 0)
        #expect(outdentCallCount == 1)
    }

    // MARK: - `inputAccessoryView` (`05-onscreen-keyboard-indent-toolbar`)

    /// `inputAccessoryView` gates on `onDismissKeyboard` — every block
    /// kind's factory passes it, not just list kinds, since a
    /// keyboard-dismiss affordance isn't list-specific. `onIndent`/
    /// `onOutdent` separately control the toolbar's *content* once
    /// `AccessoryToolbarCoordinator.configure(for:)` runs — see the tests
    /// below.
    @Test("inputAccessoryView is nil when onDismissKeyboard isn't set")
    func inputAccessoryViewIsNilWithNoOnDismissKeyboard() {
        let textView = IndentableTextView()

        #expect(textView.inputAccessoryView == nil)
    }

    @Test("inputAccessoryView is the shared coordinator's toolbar once onDismissKeyboard is set, even for a non-list block")
    func inputAccessoryViewIsSharedToolbarWhenOnDismissKeyboardSet() {
        let textView = IndentableTextView()
        textView.onDismissKeyboard = {}

        #expect(textView.inputAccessoryView === AccessoryToolbarCoordinator.shared.toolbar)
    }

    /// The whole point of today's redesign: a document with many blocks
    /// must only ever build ONE toolbar, not one per block — verified
    /// directly by checking that two entirely separate `IndentableTextView`
    /// instances (as two different blocks would have) report the exact
    /// same `inputAccessoryView` object.
    @Test("inputAccessoryView is the SAME instance across different IndentableTextViews, not rebuilt per block")
    func inputAccessoryViewIsSharedAcrossDifferentTextViews() {
        let textViewA = IndentableTextView()
        textViewA.onDismissKeyboard = {}
        let textViewB = IndentableTextView()
        textViewB.onDismissKeyboard = {}

        #expect(textViewA.inputAccessoryView === textViewB.inputAccessoryView)
    }

    // MARK: - `AccessoryToolbarCoordinator.configure(for:)`

    @Test("configure(for:) shows exactly the indent, outdent, and dismiss buttons for a list-kind block — no undo/redo")
    func configureShowsThreeButtonsForListKind() {
        let textView = IndentableTextView()
        textView.onDismissKeyboard = {}
        textView.onIndent = {}
        textView.onOutdent = {}
        let coordinator = AccessoryToolbarCoordinator.shared

        coordinator.configure(for: textView)

        let items = coordinator.toolbar.items ?? []
        // Indent, outdent, a flexible space, and dismiss — 3 actionable
        // buttons total, matching `KeyboardToolbar_States` state B/C
        // (indent/outdent/dismiss only, no undo/redo).
        let customViews = items.compactMap { $0.customView }
        #expect(customViews.count == 3)
        #expect(customViews.contains(where: { $0 === coordinator.indentButton }))
        #expect(customViews.contains(where: { $0 === coordinator.outdentButton }))
        #expect(customViews.contains(where: { $0 === coordinator.dismissButton }))
    }

    @Test("configure(for:) shows only the dismiss button for a non-list block")
    func configureShowsOnlyDismissButtonForNonListKind() {
        let textView = IndentableTextView()
        textView.onDismissKeyboard = {}
        // onIndent/onOutdent left nil, matching every non-list block's
        // factory call.
        let coordinator = AccessoryToolbarCoordinator.shared

        coordinator.configure(for: textView)

        let items = coordinator.toolbar.items ?? []
        let customViews = items.compactMap { $0.customView }
        #expect(customViews.count == 1)
        #expect(customViews.contains(where: { $0 === coordinator.dismissButton }))
        #expect(!customViews.contains(where: { $0 === coordinator.indentButton }))
        #expect(!customViews.contains(where: { $0 === coordinator.outdentButton }))
    }

    @Test("configure(for:) leaves the outdent button enabled at full opacity when canOutdent is true")
    func configureEnablesOutdentButtonAtFullOpacityWhenCanOutdentTrue() {
        let textView = IndentableTextView()
        textView.onDismissKeyboard = {}
        textView.onIndent = {}
        textView.canOutdent = true
        let coordinator = AccessoryToolbarCoordinator.shared

        coordinator.configure(for: textView)

        #expect(coordinator.outdentButton.isEnabled == true)
        #expect(coordinator.outdentButton.alpha == 1.0)
    }

    @Test("configure(for:) dims the outdent button to ~35% opacity and disables it when canOutdent is false")
    func configureDimsAndDisablesOutdentButtonWhenCanOutdentFalse() {
        let textView = IndentableTextView()
        textView.onDismissKeyboard = {}
        textView.onIndent = {}
        textView.canOutdent = false
        let coordinator = AccessoryToolbarCoordinator.shared

        coordinator.configure(for: textView)

        #expect(coordinator.outdentButton.isEnabled == false)
        // `UIButton.alpha` is a `CGFloat` backed by a 32-bit `Float` on
        // this platform, so a `0.35` `Double` literal doesn't round-trip
        // bit-for-bit — compare within a small tolerance instead of exact
        // equality.
        #expect(abs(coordinator.outdentButton.alpha - 0.35) < 0.001)
    }

    // MARK: - Shared toolbar button taps route to the active block

    @Test("The toolbar's indent button tap calls the configured block's onIndent")
    func indentButtonTapCallsActiveTextViewOnIndent() {
        let textView = IndentableTextView()
        var indentCallCount = 0
        textView.onDismissKeyboard = {}
        textView.onIndent = { indentCallCount += 1 }
        let coordinator = AccessoryToolbarCoordinator.shared
        coordinator.configure(for: textView)

        coordinator.indentButton.sendActions(for: .touchUpInside)

        #expect(indentCallCount == 1)
    }

    @Test("The toolbar's outdent button tap calls the configured block's onOutdent when canOutdent is true")
    func outdentButtonTapCallsOnOutdentWhenEnabled() {
        let textView = IndentableTextView()
        var outdentCallCount = 0
        textView.onDismissKeyboard = {}
        textView.onIndent = {}
        textView.onOutdent = { outdentCallCount += 1 }
        textView.canOutdent = true
        let coordinator = AccessoryToolbarCoordinator.shared
        coordinator.configure(for: textView)

        coordinator.outdentButton.sendActions(for: .touchUpInside)

        #expect(outdentCallCount == 1)
    }

    @Test("The toolbar's outdent button tap does not call onOutdent when canOutdent is false")
    func outdentButtonTapDoesNotCallOnOutdentWhenDisabled() {
        let textView = IndentableTextView()
        var outdentCallCount = 0
        textView.onDismissKeyboard = {}
        textView.onIndent = {}
        textView.onOutdent = { outdentCallCount += 1 }
        textView.canOutdent = false
        let coordinator = AccessoryToolbarCoordinator.shared
        coordinator.configure(for: textView)

        coordinator.outdentButton.sendActions(for: .touchUpInside)

        #expect(outdentCallCount == 0)
    }

    @Test("The toolbar's keyboard-dismiss button tap calls the configured block's onDismissKeyboard")
    func dismissButtonTapCallsOnDismissKeyboard() {
        let textView = IndentableTextView()
        var dismissCallCount = 0
        textView.onDismissKeyboard = { dismissCallCount += 1 }
        let coordinator = AccessoryToolbarCoordinator.shared
        coordinator.configure(for: textView)

        coordinator.dismissButton.sendActions(for: .touchUpInside)

        #expect(dismissCallCount == 1)
    }

    @Test("Configuring the toolbar for a different block re-targets its buttons at the new block, not the old one")
    func configuringForDifferentBlockRetargetsButtons() {
        let firstTextView = IndentableTextView()
        var firstIndentCallCount = 0
        firstTextView.onDismissKeyboard = {}
        firstTextView.onIndent = { firstIndentCallCount += 1 }

        let secondTextView = IndentableTextView()
        var secondIndentCallCount = 0
        secondTextView.onDismissKeyboard = {}
        secondTextView.onIndent = { secondIndentCallCount += 1 }

        let coordinator = AccessoryToolbarCoordinator.shared
        coordinator.configure(for: firstTextView)
        coordinator.configure(for: secondTextView)

        coordinator.indentButton.sendActions(for: .touchUpInside)

        #expect(firstIndentCallCount == 0)
        #expect(secondIndentCallCount == 1)
    }
}
