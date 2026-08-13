import SwiftUI

/// A divider block's row — a horizontal rule that's editable Markdown
/// (the Slash Command "Divider" option, §12.2) when focused, and shown
/// as a plain rule otherwise.
///
/// Built on `BlockRowChrome` like the other 7 kinds, but the only one
/// that uses its `fieldOverlay` slot and a non-default `verticalPadding`
/// — this row's render↔edit toggle (`showsDividerRule`) is uniquely
/// fragile, so the mechanism below is preserved exactly as it was worked
/// out in the previously-fixed bug it documents (`tasks/NO-007.md` §0,
/// commit `9aba150`): tapping the rendered `---` rule used to fail to
/// focus the field underneath it.
struct DividerBlockView: View {
    let item: DocumentItem
    let content: TextContent
    var focusedBlockId: FocusState<String?>.Binding
    @Binding var cursorOffsetToApply: Int?
    let onTextChange: (String) -> Void
    let onEnter: (String, Int) -> Void
    let onBackspaceAtStart: (String) -> Void

    /// Whether this row is currently showing the rendered `---` rule
    /// rather than its editable text — true whenever it isn't focused.
    private var showsDividerRule: Bool {
        focusedBlockId.wrappedValue != item.id
    }

    /// Always renders the same view tree — critically, this means the
    /// `ParagraphTextField` underneath a divider's rule is never
    /// destroyed/recreated when focus moves in and out of it. An earlier
    /// version swapped between two entirely different view trees (a bare
    /// `Rectangle` vs. the text field) based on focus, which meant tapping
    /// the rule had to simultaneously *insert* a brand-new
    /// `ParagraphTextField` *and* focus it in the same update — a known
    /// fragile SwiftUI/UIKit interop timing case (this custom
    /// `UIViewRepresentable` has no explicit `becomeFirstResponder()` of
    /// its own; it relies entirely on `.focused()` finding an
    /// already-attached view) — which silently failed to ever bring up
    /// the keyboard, making the rule untappable in practice. Keeping the
    /// text field permanently in the tree and overlaying the rule visual
    /// on top reuses the exact same always-present mechanism every other
    /// block type already focuses reliably. `BlockRowChrome.fieldOverlay`
    /// keeps that guarantee: it's drawn as an overlay on the same
    /// `ParagraphTextField` this row's chrome always mounts, never a
    /// sibling view conditionally inserted/removed.
    var body: some View {
        BlockRowChrome(
            item: item,
            content: content,
            focusedBlockId: focusedBlockId,
            cursorOffsetToApply: $cursorOffsetToApply,
            textStyle: AppTheme.Typography.body,
            // Always at full opacity (alpha 1), even while the divider
            // rule is drawn on top of it (`showsDividerRule`) — a
            // `UIViewRepresentable`-wrapped `UITextView` whose SwiftUI
            // `.opacity()` is 0 gets its real `UIView.alpha` set to 0
            // too, and UIKit's own `hitTest(_:with:)` refuses to
            // hit-test any view with `alpha < 0.01` *regardless* of
            // SwiftUI's `allowsHitTesting` — a rule
            // `.allowsHitTesting()` can't override, since it only
            // affects SwiftUI's own hit-testing pass, not UIKit's.
            // Hiding this via opacity (an earlier version of this fix)
            // therefore made it — and everything behind it — completely
            // untappable while a divider's rule was showing.
            //
            // Staying opaque keeps a tap anywhere on the row reaching
            // this real `UITextView` directly, focusing it through the
            // ordinary native UIKit path (touch → `becomeFirstResponder()`
            // → `.focused()` observes the change) — the same reliable
            // mechanism every other block type already uses. The
            // `"---"` text itself is hidden by matching its color to
            // the row's background instead (`showsDividerRule ?
            // background : primary` below), which only affects what's
            // drawn, not the view's alpha/hit-testability.
            textColor: showsDividerRule ? AppTheme.Colors.Neutral.n900 : AppTheme.Colors.Content.primary,
            verticalPadding: showsDividerRule ? AppTheme.Spacing.lg : AppTheme.Spacing.sm,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart
        ) {
            // A divider block's `"---"` text sits underneath this rule
            // (color-matched to the background, invisible) whenever it
            // isn't focused. Purely a visual overlay —
            // `allowsHitTesting(false)` lets every tap pass straight
            // through to the text field above, which reveals the
            // literal `"---"` for editing/deleting once it's focused
            // (see the field's `textColor` comment above for why taps
            // aren't handled here instead).
            Rectangle()
                .fill(AppTheme.Colors.Stroke.border)
                .frame(height: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(showsDividerRule ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}
