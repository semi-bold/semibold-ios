import Testing
import UIKit

@testable import semibold

/// Tests for `IndentableTextView` and `AccessoryToolbarCoordinator`
/// (`Views/Components/Shared/ParagraphTextField.swift`).
///
/// `IndentableTextView` is now responsible for exactly one thing: turning
/// a hardware Tab/Shift+Tab press into `onIndent`/`onOutdent`
/// (`tasks/NO-009.md` §2.1/§3.3). It has no opinion on the on-screen
/// keyboard toolbar at all — `inputAccessoryView` unconditionally returns
/// `AccessoryToolbarCoordinator.shared.toolbar`, and that coordinator is
/// configured entirely independently by `DetailScreen` observing
/// `focusedBlockId`, not by anything on this type. Simulating an actual
/// hardware key event, or mounting a real window to test focus-driven
/// behavior, isn't practical in this test target — so these instead check
/// the things that make both correct without either.
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

    // MARK: - `inputAccessoryView` — always the shared toolbar

    @Test("inputAccessoryView is always the shared coordinator's toolbar — IndentableTextView has no opinion on it")
    func inputAccessoryViewIsAlwaysTheSharedToolbar() {
        let textView = IndentableTextView()

        #expect(textView.inputAccessoryView === AccessoryToolbarCoordinator.shared.toolbar)
    }

    /// The whole point of the redesign: a document with many blocks must
    /// only ever have ONE toolbar, not one per block — verified directly
    /// by checking that two entirely separate `IndentableTextView`
    /// instances (as two different blocks would have) report the exact
    /// same `inputAccessoryView` object, with no configuration needed at
    /// all to make that true.
    @Test("inputAccessoryView is the SAME instance across different IndentableTextViews, not rebuilt per block")
    func inputAccessoryViewIsSharedAcrossDifferentTextViews() {
        let textViewA = IndentableTextView()
        let textViewB = IndentableTextView()

        #expect(textViewA.inputAccessoryView === textViewB.inputAccessoryView)
    }
}

/// Tests for `AccessoryToolbarCoordinator` itself — configured entirely
/// independently of any `IndentableTextView`, matching how `DetailScreen
/// .configureAccessoryToolbar(forBlockId:)` actually drives it (off
/// `focusedBlockId`, not off any particular block's view).
@MainActor
struct AccessoryToolbarCoordinatorTests {
    @Test("configure(...) shows exactly the indent, outdent, and dismiss buttons when onIndent is non-nil — no undo/redo")
    func configureShowsThreeButtonsForListKind() {
        let coordinator = AccessoryToolbarCoordinator.shared

        coordinator.configure(canOutdent: true, onIndent: {}, onOutdent: {}, onDismissKeyboard: {})

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

    @Test("configure(...) shows only the dismiss button when onIndent is nil — a non-list block")
    func configureShowsOnlyDismissButtonForNonListKind() {
        let coordinator = AccessoryToolbarCoordinator.shared

        coordinator.configure(canOutdent: false, onIndent: nil, onOutdent: nil, onDismissKeyboard: {})

        let items = coordinator.toolbar.items ?? []
        let customViews = items.compactMap { $0.customView }
        #expect(customViews.count == 1)
        #expect(customViews.contains(where: { $0 === coordinator.dismissButton }))
        #expect(!customViews.contains(where: { $0 === coordinator.indentButton }))
        #expect(!customViews.contains(where: { $0 === coordinator.outdentButton }))
    }

    @Test("configure(...) leaves the outdent button enabled at full opacity when canOutdent is true")
    func configureEnablesOutdentButtonAtFullOpacityWhenCanOutdentTrue() {
        let coordinator = AccessoryToolbarCoordinator.shared

        coordinator.configure(canOutdent: true, onIndent: {}, onOutdent: {}, onDismissKeyboard: {})

        #expect(coordinator.outdentButton.isEnabled == true)
        #expect(coordinator.outdentButton.alpha == 1.0)
    }

    @Test("configure(...) dims the outdent button to ~35% opacity and disables it when canOutdent is false")
    func configureDimsAndDisablesOutdentButtonWhenCanOutdentFalse() {
        let coordinator = AccessoryToolbarCoordinator.shared

        coordinator.configure(canOutdent: false, onIndent: {}, onOutdent: {}, onDismissKeyboard: {})

        #expect(coordinator.outdentButton.isEnabled == false)
        // `UIButton.alpha` is a `CGFloat` backed by a 32-bit `Float` on
        // this platform, so a `0.35` `Double` literal doesn't round-trip
        // bit-for-bit — compare within a small tolerance instead of exact
        // equality.
        #expect(abs(coordinator.outdentButton.alpha - 0.35) < 0.001)
    }

    @Test("The toolbar's indent button tap calls the configured onIndent")
    func indentButtonTapCallsConfiguredOnIndent() {
        var indentCallCount = 0
        let coordinator = AccessoryToolbarCoordinator.shared
        coordinator.configure(canOutdent: true, onIndent: { indentCallCount += 1 }, onOutdent: {}, onDismissKeyboard: {})

        coordinator.indentButton.sendActions(for: .touchUpInside)

        #expect(indentCallCount == 1)
    }

    @Test("The toolbar's outdent button tap calls the configured onOutdent when canOutdent is true")
    func outdentButtonTapCallsOnOutdentWhenEnabled() {
        var outdentCallCount = 0
        let coordinator = AccessoryToolbarCoordinator.shared
        coordinator.configure(
            canOutdent: true, onIndent: {}, onOutdent: { outdentCallCount += 1 }, onDismissKeyboard: {}
        )

        coordinator.outdentButton.sendActions(for: .touchUpInside)

        #expect(outdentCallCount == 1)
    }

    @Test("The toolbar's outdent button tap does not call onOutdent when canOutdent is false")
    func outdentButtonTapDoesNotCallOnOutdentWhenDisabled() {
        var outdentCallCount = 0
        let coordinator = AccessoryToolbarCoordinator.shared
        coordinator.configure(
            canOutdent: false, onIndent: {}, onOutdent: { outdentCallCount += 1 }, onDismissKeyboard: {}
        )

        coordinator.outdentButton.sendActions(for: .touchUpInside)

        #expect(outdentCallCount == 0)
    }

    @Test("The toolbar's keyboard-dismiss button tap calls the configured onDismissKeyboard")
    func dismissButtonTapCallsOnDismissKeyboard() {
        var dismissCallCount = 0
        let coordinator = AccessoryToolbarCoordinator.shared
        coordinator.configure(canOutdent: true, onIndent: {}, onOutdent: {}, onDismissKeyboard: { dismissCallCount += 1 })

        coordinator.dismissButton.sendActions(for: .touchUpInside)

        #expect(dismissCallCount == 1)
    }

    @Test("Re-configuring for a different block re-targets its buttons at the new closures, not the old ones")
    func reconfiguringForDifferentBlockRetargetsButtons() {
        var firstIndentCallCount = 0
        var secondIndentCallCount = 0
        let coordinator = AccessoryToolbarCoordinator.shared

        coordinator.configure(canOutdent: true, onIndent: { firstIndentCallCount += 1 }, onOutdent: {}, onDismissKeyboard: {})
        coordinator.configure(canOutdent: true, onIndent: { secondIndentCallCount += 1 }, onOutdent: {}, onDismissKeyboard: {})

        coordinator.indentButton.sendActions(for: .touchUpInside)

        #expect(firstIndentCallCount == 0)
        #expect(secondIndentCallCount == 1)
    }
}
