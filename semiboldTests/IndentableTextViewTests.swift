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
}
