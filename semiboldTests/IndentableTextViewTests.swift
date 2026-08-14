import Testing
import UIKit

@testable import semibold

/// Tests for `IndentableTextView` (`Views/Components/Shared
/// /ParagraphTextField.swift`) — the `UITextView` subclass that turns a
/// hardware Tab/Shift+Tab press into `onIndent`/`onOutdent`
/// (`tasks/NO-009.md` §2.1/§3.3).
///
/// Simulating an actual hardware key event isn't practical in this test
/// target (`04-tab-key-hardware-interception` brief's Decisions), so these
/// instead check the two things that make the interception correct without
/// one:
/// - `keyCommands` only advertises Tab/Shift+Tab when a handler is set, so
///   a block with no handler falls straight through to `UITextView`'s own
///   default Tab behavior (inserting a tab character) rather than being
///   silently swallowed.
/// - The `@objc` target-action methods those `UIKeyCommand`s point at
///   forward to `onIndent`/`onOutdent` when called directly — the same
///   call UIKit itself makes once it resolves a real Tab/Shift+Tab press
///   against `keyCommands`.
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

    /// `inputAccessoryView` reuses the exact same "`onIndent` non-`nil`"
    /// gate `keyCommands` above already uses — both agree on what counts
    /// as a list-kind block, per the brief's Decisions (don't invent a
    /// second detection mechanism). Rendering/positioning the toolbar
    /// above a real on-screen keyboard isn't practical in this test
    /// target — see this suite's doc comment — so these confirm the
    /// gating and the button-level state/wiring instead.
    @Test("inputAccessoryView is nil when onIndent isn't set, matching every non-list block")
    func inputAccessoryViewIsNilWithNoOnIndent() {
        let textView = IndentableTextView()

        #expect(textView.inputAccessoryView == nil)
    }

    @Test("inputAccessoryView is the accessory toolbar once onIndent is set, matching a focused list-kind block")
    func inputAccessoryViewIsToolbarWhenOnIndentSet() {
        let textView = IndentableTextView()
        textView.onIndent = {}

        #expect(textView.inputAccessoryView === textView.accessoryToolbar)
    }

    @Test("inputAccessoryView's toolbar shows exactly the indent, outdent, and dismiss buttons — no undo/redo")
    func accessoryToolbarHasExactlyThreeButtons() {
        let textView = IndentableTextView()
        textView.onIndent = {}

        let items = textView.accessoryToolbar.items ?? []
        // Indent, outdent, a flexible space, and dismiss — 3 actionable
        // buttons total, matching `KeyboardToolbar_States` state B/C
        // (indent/outdent/dismiss only, no undo/redo).
        let customViews = items.compactMap { $0.customView }
        #expect(customViews.count == 3)
        #expect(customViews.contains(where: { $0 === textView.indentButton }))
        #expect(customViews.contains(where: { $0 === textView.outdentButton }))
        #expect(customViews.contains(where: { $0 === textView.dismissButton }))
    }

    @Test("The toolbar's indent button tap calls onIndent")
    func indentButtonTapCallsOnIndent() {
        let textView = IndentableTextView()
        var indentCallCount = 0
        textView.onIndent = { indentCallCount += 1 }

        textView.handleIndentButtonTap()

        #expect(indentCallCount == 1)
    }

    @Test("The toolbar's outdent button tap calls onOutdent when canOutdent is true")
    func outdentButtonTapCallsOnOutdentWhenEnabled() {
        let textView = IndentableTextView()
        var outdentCallCount = 0
        textView.onOutdent = { outdentCallCount += 1 }
        textView.canOutdent = true

        textView.handleOutdentButtonTap()

        #expect(outdentCallCount == 1)
    }

    @Test("The toolbar's outdent button tap does not call onOutdent when canOutdent is false")
    func outdentButtonTapDoesNotCallOnOutdentWhenDisabled() {
        let textView = IndentableTextView()
        var outdentCallCount = 0
        textView.onOutdent = { outdentCallCount += 1 }
        textView.canOutdent = false

        textView.handleOutdentButtonTap()

        #expect(outdentCallCount == 0)
    }

    @Test("canOutdent = true leaves the outdent button enabled at full opacity")
    func canOutdentTrueEnablesOutdentButtonAtFullOpacity() {
        let textView = IndentableTextView()

        textView.canOutdent = true

        #expect(textView.outdentButton.isEnabled == true)
        #expect(textView.outdentButton.alpha == 1.0)
    }

    @Test("canOutdent = false dims the outdent button to ~35% opacity and disables it")
    func canOutdentFalseDimsAndDisablesOutdentButton() {
        let textView = IndentableTextView()

        textView.canOutdent = false

        #expect(textView.outdentButton.isEnabled == false)
        // `UIButton.alpha` is a `CGFloat` backed by a 32-bit `Float` on
        // this platform, so a `0.35` `Double` literal doesn't round-trip
        // bit-for-bit — compare within a small tolerance instead of exact
        // equality.
        #expect(abs(textView.outdentButton.alpha - 0.35) < 0.001)
    }

    @Test("The toolbar's keyboard-dismiss button tap calls onDismissKeyboard")
    func dismissButtonTapCallsOnDismissKeyboard() {
        let textView = IndentableTextView()
        var dismissCallCount = 0
        textView.onDismissKeyboard = { dismissCallCount += 1 }

        textView.handleDismissButtonTap()

        #expect(dismissCallCount == 1)
    }
}
