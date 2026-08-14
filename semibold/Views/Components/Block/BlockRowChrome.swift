import SwiftUI

/// What a block row's leading column (before its text) shows — a plain
/// value rather than a `View`-typed closure, so every per-kind block
/// (`ParagraphBlockView`, `HeadingBlockView`, `QuoteBlockView`,
/// `ChecklistBlockView`, `BulletedListBlockView`, `NumberedListBlockView`,
/// `CodeBlockView`) constructs the exact same `BlockRowChrome` concrete
/// type, just with a different `leadingContent` value. That uniformity is
/// what lets `DetailScreen.blockRow(for:content:)` switch between kinds
/// for the same block id without SwiftUI tearing down and rebuilding the
/// `ParagraphTextField` underneath — see `BlockRowChrome`'s doc comment.
enum BlockLeadingContent {
    case none
    case marker(String)
    case checkbox(isChecked: Bool, action: () -> Void)
    case quoteBar
}

/// The scaffold every editable block row shares, regardless of
/// `content.textKind` — the row's outer padding/background, the
/// `ParagraphTextField` wiring (focus binding, cursor placement, and the
/// Enter/Backspace/text-change callbacks `DetailViewModel` drives), and a
/// `leadingContent` slot for whatever a given kind puts before its text.
///
/// Each of the 8 per-kind views under `Views/Components/Block/`
/// (`ParagraphBlockView`, `HeadingBlockView`, `QuoteBlockView`,
/// `ChecklistBlockView`, `BulletedListBlockView`, `NumberedListBlockView`,
/// `CodeBlockView`, `DividerBlockView`) is a plain `enum` with a static
/// `chrome(...)` factory that returns `BlockRowChrome` directly — not a
/// `View` struct wrapping it. That matters: `BlockRowChrome` is a single
/// concrete (non-generic) type, so every one of those 8 factories returns
/// the *same* type. `DetailScreen.blockRow(for:content:)` switches on
/// `content.textKind` and calls straight into whichever factory applies,
/// so the `@ViewBuilder switch`'s leaf type is `BlockRowChrome` in every
/// case. SwiftUI's diffing is structural, not value-based — when a block's
/// `content.textKind` changes (e.g. backspacing an empty list item back to
/// a paragraph, `DetailViewModel.exitEmptyListItem`), the switch takes a
/// different case, but since every case still yields the same concrete
/// `BlockRowChrome` type at that tree position, SwiftUI treats it as the
/// same view re-rendered with new parameter values, not a different view
/// replacing it. That preserves `ParagraphTextField`'s backing
/// `UIViewRepresentable`/`UITextView` identity — and with it, keyboard
/// focus — across the kind change. Routing through 7 distinct `View`
/// struct types (the earlier design) broke exactly this: switching between
/// distinct concrete types at the same tree position, even ones that
/// looked interchangeable, is a different view to SwiftUI, so it tore the
/// text field down and rebuilt it, silently dropping focus.
struct BlockRowChrome: View {
    let item: DocumentItem
    let content: TextContent
    var focusedBlockId: FocusState<String?>.Binding
    @Binding var cursorOffsetToApply: Int?

    /// This kind's typography — e.g. `HeadingBlockView` maps
    /// `content.headingLevel` to `AppTheme.Typography.heading1`/
    /// `.heading2`/`.title`; every other kind passes `.body`.
    let textStyle: TextStyleToken
    /// This kind's text color — `QuoteBlockView` passes `.secondary` to
    /// dim its quoted text; every other kind uses the default `.primary`.
    /// Ignored for a divider row while its rule is showing — see
    /// `resolvedTextColor`.
    var textColor: Color = AppTheme.Colors.Content.primary
    /// Whether this kind's text is monospaced — `true` only for
    /// `CodeBlockView`.
    var isMonospaced: Bool = false
    /// Whether this row uses a code block's distinguishing surface
    /// background (`n700`) instead of the usual `n900` — `true` only for
    /// `CodeBlockView`. A plain flag rather than a `content.textKind`
    /// comparison, so this view stays kind-agnostic.
    var isCodeBlock: Bool = false
    /// What this row's leading column shows before its text — a marker
    /// (bullet/number), a checkbox, a quote bar, or nothing. See
    /// `BlockLeadingContent`.
    var leadingContent: BlockLeadingContent = .none
    /// True only for `DividerBlockView` — see `showsDividerRule` and
    /// `dividerRuleOverlay` for what this switches on. Every other kind
    /// leaves this at the default `false`.
    var isDividerRow: Bool = false
    /// This row's nesting depth (0 for a top-level item), from
    /// `DetailViewModel.depth(forItemId:)` — only the three list-kind
    /// factories (`BulletedListBlockView`/`NumberedListBlockView`/
    /// `ChecklistBlockView`) ever pass a nonzero value; every other kind
    /// leaves this at the default `0`, since non-list blocks never nest
    /// (`tasks/NO-009.md` §2.2). Adds `depth * AppTheme.Spacing.lg` of
    /// leading padding on top of the row's existing horizontal padding —
    /// see `body`'s `.padding(.leading, ...)` — so a depth-0 row is
    /// pixel-identical to before this parameter existed.
    var depth: Int = 0

    let onTextChange: (String) -> Void
    let onEnter: (String, Int) -> Void
    let onBackspaceAtStart: (String) -> Void

    /// Reads straight from `content.plainText` (the view model's source
    /// of truth) rather than mirroring it into a separate local `@State`
    /// — keystrokes still flow out via `onTextChange`, so this binding's
    /// setter is a no-op, and `ParagraphTextField.updateUIView` picks up
    /// the authoritative value on every render.
    ///
    /// A local echo used to exist here (back when this was `BlockRow`),
    /// kept in sync via `.onChange(of: content.plainText)`, but that only
    /// fires when the value actually differs between renders — which
    /// silently broke the Slash Command flow: typing `/` writes `"/"`
    /// into the `UITextView` directly (see
    /// `ParagraphTextField.Coordinator.textViewDidChange`), then
    /// `updateBlockText` clears the block straight back to the empty
    /// string it already was (`"" → "/" → ""`, a net no-op from the view
    /// model's perspective), so the `onChange` never fired and the stray
    /// `/` stuck around in the text field even after picking a type from
    /// the sheet. Deriving directly from `content.plainText` removes the
    /// second copy of the truth instead of patching the sync.
    private var text: Binding<String> {
        Binding(get: { content.plainText }, set: { _ in })
    }

    /// Whether this row is currently showing the rendered `---` rule
    /// rather than its editable text — true only for a divider row that
    /// isn't focused. See `DividerBlockView`'s doc comment for why the
    /// rule is drawn as an overlay on the always-mounted text field rather
    /// than swapped in for it.
    private var showsDividerRule: Bool {
        isDividerRow && focusedBlockId.wrappedValue != item.id
    }

    /// A divider's `"---"` text is color-matched to the row's background
    /// (invisible) while its rule is showing — see `dividerRuleOverlay`'s
    /// doc comment for why it's hidden this way instead of via opacity.
    private var resolvedTextColor: Color {
        showsDividerRule ? AppTheme.Colors.Neutral.n900 : textColor
    }

    /// Every kind but a showing divider rule uses the default
    /// `AppTheme.Spacing.sm`; a divider needs the extra breathing room a
    /// rendered horizontal rule wants over an ordinary line of text.
    private var resolvedVerticalPadding: CGFloat {
        guard isDividerRow else { return AppTheme.Spacing.sm }
        return showsDividerRule ? AppTheme.Spacing.lg : AppTheme.Spacing.sm
    }

    /// One `AppTheme.Spacing.lg` step per nesting level — matches the
    /// `AppTheme.Spacing.lg` `minWidth` `leadingColumnView` already gives
    /// each list kind's marker/checkbox column, so a nested item's marker
    /// lines up one full marker-column-width in from its parent's rather
    /// than an arbitrary new spacing value (`03-depth-padding-rendering`
    /// brief's Decisions). Additive to the row's existing horizontal
    /// padding, not a replacement — `depth == 0` adds zero, keeping today's
    /// layout pixel-identical.
    private var indentPadding: CGFloat {
        CGFloat(depth) * AppTheme.Spacing.lg
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            // No spacing beyond the leading column's own `minWidth`
            // (when it has one) — a gap on top of that would leave too
            // much empty space between a marker (bullet/number/checkbox/
            // quote bar) and its text.
            HStack(alignment: .top, spacing: 0) {
                leadingColumnView

                ParagraphTextField(
                    text: text,
                    textStyle: textStyle,
                    textColor: resolvedTextColor,
                    isMonospaced: isMonospaced,
                    onTextChange: onTextChange,
                    onEnter: { cursorOffset in
                        onEnter(content.plainText, cursorOffset)
                    },
                    onBackspaceAtStart: {
                        onBackspaceAtStart(content.plainText)
                    },
                    cursorOffsetToApply: focusedBlockId.wrappedValue == item.id ? $cursorOffsetToApply : .constant(nil)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused(focusedBlockId, equals: item.id)
                .overlay(alignment: .leading) { dividerRuleOverlay }
            }
        }
        .padding(.leading, indentPadding)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, resolvedVerticalPadding)
        .background(isCodeBlock ? AppTheme.Colors.Neutral.n700 : AppTheme.Colors.Neutral.n900)
    }

    @ViewBuilder
    private var leadingColumnView: some View {
        switch leadingContent {
        case .none:
            EmptyView()
        case .marker(let marker):
            Text(marker)
                .appTextStyle(textStyle)
                .foregroundStyle(AppTheme.Colors.Content.primary)
                .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
        case .checkbox(let isChecked, let action):
            Button(action: action) {
                Image(systemName: isChecked ? "checkmark.square" : "square")
                    .foregroundStyle(isChecked ? AppTheme.Colors.accent : AppTheme.Colors.Content.secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
            .frame(height: textStyle.lineHeight, alignment: .center)
        case .quoteBar:
            Rectangle()
                .fill(AppTheme.Colors.Stroke.border)
                .frame(width: AppTheme.Spacing.xs)
                .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
        }
    }

    /// A divider block's `"---"` text (hidden via `resolvedTextColor`,
    /// not opacity — see that property's doc comment; the short version:
    /// a `UIViewRepresentable`-wrapped `UITextView` at `opacity(0)` gets
    /// its real `UIView.alpha` set to 0 too, and UIKit's own
    /// `hitTest(_:with:)` refuses to hit-test any view with
    /// `alpha < 0.01` regardless of SwiftUI's `allowsHitTesting`, making
    /// it and everything behind it untappable) sits underneath this rule
    /// whenever the row isn't focused. Purely a visual overlay —
    /// `allowsHitTesting(false)` lets every tap pass straight through to
    /// the always-mounted text field above, which is what makes tapping
    /// the rendered rule reliably focus it (`tasks/NO-007.md` §0, commit
    /// `9aba150`).
    @ViewBuilder
    private var dividerRuleOverlay: some View {
        if isDividerRow {
            Rectangle()
                .fill(AppTheme.Colors.Stroke.border)
                .frame(height: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(showsDividerRule ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}
