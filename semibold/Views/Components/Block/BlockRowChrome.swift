import SwiftUI

/// The scaffold every editable block row shares, regardless of
/// `content.textKind` — the row's outer padding/background, the
/// `ParagraphTextField` wiring (focus binding, cursor placement, and the
/// Enter/Backspace/text-change callbacks `DetailViewModel` drives), and a
/// `leadingColumn` slot for whatever a given kind puts before its text.
///
/// Each of the 7 per-kind views under `Views/Components/Block/`
/// (`ParagraphBlockView`, `HeadingBlockView`, `QuoteBlockView`,
/// `ChecklistBlockView`, `BulletedListBlockView`, `NumberedListBlockView`,
/// `CodeBlockView`) plugs in only what actually varies for its kind —
/// typography (`textStyle`), text color, monospacing, the code-block
/// background, and the leading column's content — via this view's plain
/// parameters and its `leadingColumn` `@ViewBuilder` slot. This view
/// itself never branches on `content.textKind`; routing which per-kind
/// view a block uses is `DetailScreen.blockList`'s job.
///
/// `divider` isn't one of the 7 kinds yet (`03-divider-block-split`) —
/// it still renders through its own dedicated `DividerBlockRow` in
/// `DetailScreen.swift`, which doesn't use this chrome.
///
/// A kind with no leading-column content (paragraph, heading, code
/// block) simply doesn't pass a `leadingColumn` closure — the default
/// `EmptyView()` takes up no space in the row's leading `HStack` at all,
/// matching how those kinds render today with no leading-column element
/// in the tree whatsoever. A kind that does have leading content (list
/// marker, checkbox, quote bar) is responsible for its own
/// `frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)` sizing on
/// whatever it passes in — that sizing only ever applied to those kinds
/// to begin with, so this chrome doesn't force it onto every row.
struct BlockRowChrome<LeadingColumn: View>: View {
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
    var textColor: Color = AppTheme.Colors.Content.primary
    /// Whether this kind's text is monospaced — `true` only for
    /// `CodeBlockView`.
    var isMonospaced: Bool = false
    /// Whether this row uses a code block's distinguishing surface
    /// background (`n700`) instead of the usual `n900` — `true` only for
    /// `CodeBlockView`. A plain flag rather than a `content.textKind`
    /// comparison, so this view stays kind-agnostic.
    var isCodeBlock: Bool = false

    let onTextChange: (String) -> Void
    let onEnter: (String, Int) -> Void
    let onBackspaceAtStart: (String) -> Void

    @ViewBuilder var leadingColumn: () -> LeadingColumn

    init(
        item: DocumentItem,
        content: TextContent,
        focusedBlockId: FocusState<String?>.Binding,
        cursorOffsetToApply: Binding<Int?>,
        textStyle: TextStyleToken,
        textColor: Color = AppTheme.Colors.Content.primary,
        isMonospaced: Bool = false,
        isCodeBlock: Bool = false,
        onTextChange: @escaping (String) -> Void,
        onEnter: @escaping (String, Int) -> Void,
        onBackspaceAtStart: @escaping (String) -> Void,
        @ViewBuilder leadingColumn: @escaping () -> LeadingColumn = { EmptyView() }
    ) {
        self.item = item
        self.content = content
        self.focusedBlockId = focusedBlockId
        self._cursorOffsetToApply = cursorOffsetToApply
        self.textStyle = textStyle
        self.textColor = textColor
        self.isMonospaced = isMonospaced
        self.isCodeBlock = isCodeBlock
        self.onTextChange = onTextChange
        self.onEnter = onEnter
        self.onBackspaceAtStart = onBackspaceAtStart
        self.leadingColumn = leadingColumn
    }

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

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            // No spacing beyond the leading column's own `minWidth`
            // (when it has one) — a gap on top of that would leave too
            // much empty space between a marker (bullet/number/checkbox/
            // quote bar) and its text.
            HStack(alignment: .top, spacing: 0) {
                leadingColumn()

                ParagraphTextField(
                    text: text,
                    textStyle: textStyle,
                    textColor: textColor,
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
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(isCodeBlock ? AppTheme.Colors.Neutral.n700 : AppTheme.Colors.Neutral.n900)
    }
}
