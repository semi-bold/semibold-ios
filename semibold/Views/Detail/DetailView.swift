import SwiftUI

/// The document editor screen: a document's title, date, and its blocks.
///
/// Matches the `iOS_Editor` artboard (`../sketch-autokit/screens/wireframe.py`)
/// — the reference screen for `Planning_4_BlockCreateFlow` — with a nav
/// bar, a title area showing the document's title and last-updated date,
/// and a scrolling list of the document's blocks below a divider.
///
/// Each block is an editable text input (callout ② "입력 중인 블록과
/// 캐럿"). Pressing Enter/Return splits the current block's text at the
/// cursor and creates a new paragraph block right below it, moving focus
/// there (PLANNING §5.4/§13.1). Pressing Backspace at the very start of a
/// block merges it into the previous block (or deletes it if empty),
/// moving focus to the merge point (PLANNING §6.3/§13.1). Block-type
/// conversions and a reorder UI (`Planning_4_BlockCreateFlow` callouts
/// ①③⑤) land in later acceptance criteria — every block is a plain
/// paragraph for now.
struct DetailView: View {
    @State private var viewModel: DetailViewModel
    @FocusState private var focusedBlockId: String?
    @State private var cursorOffsetToApply: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(document: Document) {
        _viewModel = State(initialValue: DetailViewModel(document: document))
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            titleArea

            Rectangle()
                .fill(AppTheme.Colors.Stroke.divider)
                .frame(height: 1)

            blockList
        }
        .background(AppTheme.Colors.Neutral.n900)
        .background(keyboardShortcuts)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.load()
        }
        .onChange(of: viewModel.focusedBlockId) { _, newValue in
            guard let newValue else { return }
            focusedBlockId = newValue
            cursorOffsetToApply = viewModel.focusedBlockCursorOffset
            viewModel.focusHandled()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Flush any debounced block edits before the app moves to the
            // background, so nothing typed right before backgrounding is
            // lost (PLANNING §11.2 "앱 백그라운드 진입: pending change
            // flush").
            if newPhase == .background {
                viewModel.flushPendingChanges()
            }
        }
        .onDisappear {
            // Also flush when leaving this screen (e.g. tapping "< Back")
            // so an edit made just before navigating away isn't lost while
            // its debounce timer is still pending.
            viewModel.flushPendingChanges()
        }
        .sheet(isPresented: slashCommandSheetPresented) {
            SlashCommandSheet { option in
                if let blockId = viewModel.slashCommandBlockId {
                    viewModel.convertBlock(blockId, toSlashCommandOption: option)
                }
            }
        }
        .alert(
            "Error",
            isPresented: errorAlertPresented,
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: { message in
            // §15.2 "저장 실패"/"삭제 실패" — shown when a block edit,
            // create, or delete couldn't be persisted.
            Text(message)
        }
        .alert(
            "잠금",
            isPresented: lockNoticeAlertPresented,
            presenting: viewModel.lockNotice
        ) { _ in
            Button("OK") {
                viewModel.lockNotice = nil
            }
        } message: { message in
            // `Planning_9_SwipeActionFlow` callout ⑤ — Secret Lock's
            // actual encryption is out of scope for now, so the "잠금"
            // swipe action just confirms it's coming rather than doing
            // nothing.
            Text(message)
        }
    }

    /// Whether the §15.2 save/delete-failure alert is shown — driven by
    /// `viewModel.errorMessage`. Dismissing the alert (the "OK" button, or
    /// swiping it away) clears the message so it doesn't reappear.
    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    /// Whether the Slash Command bottom sheet (§12.2/§13.1) is shown —
    /// driven by `viewModel.slashCommandBlockId`, set when the user types a
    /// lone `/` into an empty paragraph block. Swiping the sheet away (the
    /// `false` write below) clears that id via `dismissSlashCommand()` so
    /// it doesn't reopen.
    private var slashCommandSheetPresented: Binding<Bool> {
        Binding(
            get: { viewModel.slashCommandBlockId != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissSlashCommand()
                }
            }
        )
    }

    /// Whether the "잠금" swipe action's not-yet-supported notice is
    /// shown — driven by `viewModel.lockNotice`. Dismissing it clears the
    /// message so it doesn't reappear.
    private var lockNoticeAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.lockNotice != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.lockNotice = nil
                }
            }
        )
    }

    // MARK: - macOS keyboard shortcuts

    /// Invisible buttons that exist only to register the macOS
    /// keyboard shortcuts from §13.2 — Cmd+B/I/K and Cmd+Option+1/2/3 — and
    /// apply them to whichever block currently has keyboard focus.
    ///
    /// `ParagraphTextField` is a `UITextView` wrapper that doesn't surface
    /// these key combinations to SwiftUI directly, so `.keyboardShortcut()`
    /// on buttons scoped to this screen is the standard SwiftUI pattern for
    /// "while the editor is visible, this key combo does X." The buttons
    /// are zero-sized and hidden from accessibility — they're never seen or
    /// tapped, only triggered by their shortcut.
    private var keyboardShortcuts: some View {
        Group {
            Button("Bold") {
                guard let blockId = focusedBlockId else { return }
                viewModel.toggleBoldOnBlock(blockId)
            }
            .keyboardShortcut("b", modifiers: [.command])

            Button("Italic") {
                guard let blockId = focusedBlockId else { return }
                viewModel.toggleItalicOnBlock(blockId)
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button("Link") {
                guard let blockId = focusedBlockId else { return }
                viewModel.toggleLinkOnBlock(blockId)
            }
            .keyboardShortcut("k", modifiers: [.command])

            ForEach(1...3, id: \.self) { level in
                Button("Heading \(level)") {
                    guard let blockId = focusedBlockId else { return }
                    viewModel.convertBlockToHeading(blockId, level: level)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: [.command, .option])
            }
        }
        .frame(width: 0, height: 0)
        .hidden()
        .accessibilityHidden(true)
    }

    // MARK: - Nav bar

    /// Top bar with a back button to return to wherever this document was
    /// opened from — `HomeView`'s document list for a root-level document,
    /// or the owning `FolderContentsView` for one filed inside a folder, in
    /// which case the label names that folder instead of staying generic
    /// (`viewModel.backButtonText`, mirroring
    /// `Planning_6_FolderNavigationFlow` callout ①).
    ///
    /// The wireframe also shows a "잠금" (lock) button on the right
    /// (`DocLockBtn`) — that's Secret Lock, explicitly out of this
    /// planning's scope (callout ④ of `Planning_4_BlockCreateFlow`,
    /// PLANNING §1.2), so it's omitted here.
    ///
    /// A trailing share button (§10.3 "파일 저장 또는 공유") is added on the
    /// opposite side from the back button — no `Screen_*`/`Planning_N_*Flow`
    /// artboard defines an export affordance for `iOS_Editor` (only the
    /// "잠금" button is shown there, and that's the out-of-scope Secret Lock
    /// button above), so this reuses the back button's row/typography and a
    /// standard SF Symbol share icon rather than inventing new layout.
    private var navBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text(viewModel.backButtonText)
                        .appTextStyle(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.accent)
                }

                Spacer()

                exportShareLink
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 52)

            Rectangle()
                .fill(AppTheme.Colors.Stroke.divider)
                .frame(height: 1)
        }
        .background(AppTheme.Colors.Neutral.n800)
    }

    /// "파일 저장 또는 공유" (§10.3's final step): shares the document's
    /// content as a Markdown `.md` file, using `ShareLink`'s standard sheet —
    /// which already covers both "Save to Files" and sharing to other apps
    /// from one control.
    ///
    /// `ShareLink(item:)` takes a `MarkdownDocumentExport` (a `Transferable`
    /// wrapping this document's title and its currently-loaded
    /// `items`/`textContents`/`marksByItemId`) rather than a pre-rendered
    /// file `URL`. That defers `MarkdownExporter.render` and the
    /// temporary-file write to `MarkdownDocumentExport`'s `exporting` closure,
    /// which only runs when the user taps this button and the system actually
    /// requests the export — not on every `body` re-evaluation (e.g. every
    /// keystroke).
    private var exportShareLink: some View {
        let export = MarkdownDocumentExport(
            documentTitle: viewModel.document.title,
            items: viewModel.items,
            textContents: viewModel.textContents,
            marksByItemId: viewModel.marksByItemId
        )
        return ShareLink(
            item: export,
            preview: SharePreview(
                MarkdownDocumentExport.fileName(forDocumentTitle: viewModel.document.title)
            )
        ) {
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(AppTheme.Colors.accent)
        }
    }

    // MARK: - Title area

    /// Document title and last-updated date, matching `TitleArea` in the
    /// wireframe.
    private var titleArea: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(viewModel.document.title)
                .appTextStyle(AppTheme.Typography.heading2)
                .foregroundStyle(AppTheme.Colors.Content.primary)

            Text(viewModel.document.updatedAt.formatted(date: .numeric, time: .omitted))
                .appTextStyle(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.Content.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.sm)
        .frame(height: 72, alignment: .topLeading)
        .background(AppTheme.Colors.Neutral.n900)
    }

    // MARK: - Block list

    /// The document's blocks, matching the wireframe's stacked
    /// `Block_*` rows — each one an editable paragraph input
    /// (callout ②). `load()` guarantees at least one (empty) block exists,
    /// so this list is never empty by the time it's shown.
    private var blockList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.items) { item in
                    BlockRow(
                        item: item,
                        content: viewModel.textContent(forItemId: item.id),
                        numberedListNumber: viewModel.numberedListNumber(forItemId: item.id),
                        focusedBlockId: $focusedBlockId,
                        cursorOffsetToApply: $cursorOffsetToApply,
                        onTextChange: { text in
                            viewModel.updateBlockText(item.id, text: text)
                        },
                        onEnter: { text, cursorOffset in
                            viewModel.insertBlock(after: item.id, currentText: text, cursorOffset: cursorOffset)
                        },
                        onBackspaceAtStart: { text in
                            viewModel.mergeOrDeleteBlock(item.id, currentText: text)
                        },
                        onToggleChecklist: {
                            viewModel.toggleChecklistItem(blockId: item.id)
                        },
                        onLockTapped: {
                            viewModel.lockBlockTapped(item.id)
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.Neutral.n900)
        .overlay(alignment: .topLeading) {
            if viewModel.showsEmptyContentPlaceholder {
                emptyContentPlaceholder
            }
        }
    }

    /// Empty-state hint shown over the document's single empty paragraph
    /// block (§15.1, "문서 내용이 없을 때": "Markdown으로 작성하거나 / 를 눌러
    /// 블록을 추가하세요.").
    ///
    /// Positioned like a text field's placeholder text — sitting on top of
    /// that block's (currently empty) input at the same padding/typography
    /// it uses, so it reads as "type here" rather than a separate message.
    /// `allowsHitTesting(false)` lets taps pass through to the block's text
    /// input underneath, and it disappears as soon as the user types
    /// anything (Markdown) or presses `/` (which opens the Slash Command
    /// sheet from the previous AC).
    private var emptyContentPlaceholder: some View {
        Text("Markdown으로 작성하거나 / 를 눌러 블록을 추가하세요.")
            .appTextStyle(AppTheme.Typography.body)
            .foregroundStyle(AppTheme.Colors.Content.secondary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A single editable block row, matching the wireframe's `Block_*` groups:
/// a text input for the block's content with a divider below
/// (`Block_Editing`'s cursor when focused — callout ②).
///
/// Bulleted/numbered list items show a `•`/`<n>.` marker before the
/// editable text (§7.1/§7.3's `- item` / `1. item` syntax). Checklist
/// items show a tappable checkbox in that same leading column — tapping it
/// toggles the task's done/not-done state (§7.1). Blockquote blocks show a
/// vertical rule in that same leading column and dim the quoted text,
/// marking it as a quote (§7.1/§7.3's `> quote` syntax). Code blocks show
/// their code in a monospaced font on a distinguishing surface background
/// (§7.1/§7.3's ` ```lang ` syntax).
///
/// Backed by a `DocumentItem` (`item` — position/hierarchy) plus that
/// item's `TextContent` (`content` — the actual text), per
/// `DetailViewModel`'s NO-005 model, rather than the old single
/// `DocumentBlock`. `content.textKind` is compared against `TextItemKind`'s
/// constants rather than a closed `BlockType` enum — see
/// `DetailViewModel.swift`'s `TextItemKind` doc comment.
private struct BlockRow: View {
    let item: DocumentItem
    let content: TextContent
    /// This row's position among consecutive numbered-list-item siblings
    /// (`DetailViewModel.numberedListNumber(forItemId:)`) — only meaningful
    /// when `content.textKind == TextItemKind.numberedListItem`.
    let numberedListNumber: Int
    var focusedBlockId: FocusState<String?>.Binding
    @Binding var cursorOffsetToApply: Int?
    let onTextChange: (String) -> Void
    let onEnter: (String, Int) -> Void
    let onBackspaceAtStart: (String) -> Void
    let onToggleChecklist: () -> Void
    let onLockTapped: () -> Void

    /// Reads straight from `content.plainText` (the view model's source of
    /// truth) rather than mirroring it into a separate local `@State` —
    /// keystrokes still flow out via `onTextChange`, so this binding's
    /// setter is a no-op, and `ParagraphTextField.updateUIView` picks up
    /// the authoritative value on every render.
    ///
    /// A local echo used to exist here, kept in sync via
    /// `.onChange(of: content.plainText)`, but that only fires when the
    /// value actually differs between renders — which silently broke the
    /// Slash Command flow: typing `/` writes `"/"` into the `UITextView`
    /// directly (see `ParagraphTextField.Coordinator.textViewDidChange`),
    /// then `updateBlockText` clears the block straight back to the
    /// empty string it already was (`"" → "/" → ""`, a net no-op from the
    /// view model's perspective), so the `onChange` never fired and the
    /// stray `/` stuck around in the text field even after picking a type
    /// from the sheet. Deriving directly from `content.plainText` removes
    /// the second copy of the truth instead of patching the sync.
    private var text: Binding<String> {
        Binding(get: { content.plainText }, set: { _ in })
    }

    init(
        item: DocumentItem,
        content: TextContent,
        numberedListNumber: Int,
        focusedBlockId: FocusState<String?>.Binding,
        cursorOffsetToApply: Binding<Int?>,
        onTextChange: @escaping (String) -> Void,
        onEnter: @escaping (String, Int) -> Void,
        onBackspaceAtStart: @escaping (String) -> Void,
        onToggleChecklist: @escaping () -> Void,
        onLockTapped: @escaping () -> Void
    ) {
        self.item = item
        self.content = content
        self.numberedListNumber = numberedListNumber
        self.focusedBlockId = focusedBlockId
        self._cursorOffsetToApply = cursorOffsetToApply
        self.onTextChange = onTextChange
        self.onEnter = onEnter
        self.onBackspaceAtStart = onBackspaceAtStart
        self.onToggleChecklist = onToggleChecklist
        self.onLockTapped = onLockTapped
    }

    /// The typography this block's text is shown in — heading levels 1-3
    /// map to `AppTheme.Typography.heading1`/`.heading2`/`.heading3`
    /// (§7.1/§7.3's `# `/`## `/`### ` conversions); every other block type
    /// uses `.body`.
    private var textStyle: TextStyleToken {
        guard content.textKind == TextItemKind.heading else { return AppTheme.Typography.body }
        switch content.headingLevel {
        case 1: return AppTheme.Typography.heading1
        case 2: return AppTheme.Typography.heading2
        default: return AppTheme.Typography.title
        }
    }

    /// The marker shown before a list item's text — a bullet for a
    /// bulleted list item, the item's number followed by a period for a
    /// numbered list item (§7.1/§7.3's `- item` / `1. item` syntax). `nil`
    /// for every other block type, which shows no marker. Checklist items
    /// show a checkbox instead, and blockquote blocks show a vertical
    /// rule, in the same leading column — see `body`.
    private var listMarker: String? {
        switch content.textKind {
        case TextItemKind.bulletedListItem: return "•"
        case TextItemKind.numberedListItem: return "\(numberedListNumber)."
        default: return nil
        }
    }

    /// The color this block's text is shown in — blockquote text is
    /// dimmed (`AppTheme.Colors.Content.secondary`) to read as a quote, distinct from
    /// the surrounding paragraph text; every other block type uses the
    /// primary text color.
    private var textColor: Color {
        content.textKind == TextItemKind.quote ? AppTheme.Colors.Content.secondary : AppTheme.Colors.Content.primary
    }

    /// Whether this row's text is shown in a monospaced font — `true` for
    /// code blocks (§7.1/§7.3's ` ```lang ` syntax), so code reads
    /// distinctly from prose.
    private var isCodeBlock: Bool {
        content.textKind == TextItemKind.codeBlock
    }

    /// Whether this block is a divider — rendered as a horizontal rule
    /// with no editable text (the Slash Command "Divider" option, §12.2).
    private var isDivider: Bool {
        content.textKind == TextItemKind.divider
    }

    var body: some View {
        if isDivider {
            dividerBody
        } else {
            SwipeToRevealLockAction(onLockTapped: onLockTapped) {
                editableBody
            }
        }
    }

    /// A divider block's row: a horizontal rule, matching the visual
    /// language of a Markdown `---` divider. Not editable — there's no
    /// `ParagraphTextField` for a divider since it has no text content
    /// (§8.1 `{ type: "divider" }`).
    private var dividerBody: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppTheme.Colors.Stroke.border)
                .frame(height: 1)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)

            Rectangle()
                .fill(AppTheme.Colors.Stroke.divider)
                .frame(height: 1)
        }
        .background(AppTheme.Colors.Neutral.n900)
    }

    private var editableBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                // A code block's fence language identifier (e.g. `swift`
                // for ` ```swift `) isn't modeled on `TextContent` — see
                // `DetailViewModel.updateBlockText`'s doc comment — so
                // unlike the pre-NO-005 editor, no language caption shows
                // above the code here.

                // No spacing beyond the marker column's own `minWidth`
                // below (unchanged) — the previous `AppTheme.Spacing.sm`
                // (8pt) gap on top of that column left too much empty
                // space between a marker (bullet/number/checkbox/quote
                // bar) and its text.
                HStack(alignment: .top, spacing: 0) {
                    if let listMarker {
                        Text(listMarker)
                            .appTextStyle(textStyle)
                            .foregroundStyle(AppTheme.Colors.Content.primary)
                            .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
                    } else if content.textKind == TextItemKind.checklist {
                        let isChecked = content.isChecked ?? false
                        Button(action: onToggleChecklist) {
                            Image(systemName: isChecked ? "checkmark.square" : "square")
                                .foregroundStyle(isChecked ? AppTheme.Colors.accent : AppTheme.Colors.Content.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
                        .frame(height: textStyle.lineHeight, alignment: .center)
                    } else if content.textKind == TextItemKind.quote {
                        Rectangle()
                            .fill(AppTheme.Colors.Stroke.border)
                            .frame(width: AppTheme.Spacing.xs)
                            .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
                    }

                    ParagraphTextField(
                        text: text,
                        textStyle: textStyle,
                        textColor: textColor,
                        isMonospaced: isCodeBlock,
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
            .padding(.vertical, AppTheme.Spacing.md)
            .background(isCodeBlock ? AppTheme.Colors.Neutral.n700 : AppTheme.Colors.Neutral.n900)

            Rectangle()
                .fill(AppTheme.Colors.Stroke.divider)
                .frame(height: 1)
        }
        .background(AppTheme.Colors.Neutral.n900)
    }
}

/// Reveals a "잠금" (lock) button when its content is swiped left, matching
/// `iOS_SwipeAction`'s `SwipeAction_Lock` layer (`Planning_9_SwipeActionFlow`
/// callout ⑤): an 80pt-wide button with a lock icon and label.
///
/// `DetailView`'s block list is a `ScrollView`/`LazyVStack` rather than a
/// `List`, so the standard `.swipeActions(edge:)` modifier (used for the
/// folder/document row actions elsewhere in this app) isn't available
/// here — it only attaches to `List` rows. This reproduces the same
/// swipe-to-reveal interaction with a `DragGesture` that drags `content`
/// left to reveal the button underneath, snapping open past a small
/// threshold and closed otherwise, the same left-swipe gesture pattern
/// the wireframe shows for both HomeView rows and editor blocks.
private enum SwipeToRevealLockActionLayout {
    /// The lock button's fixed width, matching `SwipeAction_Lock`'s `w=80`
    /// frame in the wireframe (same width as the HomeView row actions).
    static let actionWidth: CGFloat = 80
}

private struct SwipeToRevealLockAction<Content: View>: View {
    let onLockTapped: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragTranslation: CGFloat = 0
    @State private var isRevealed = false

    private var revealOffset: CGFloat {
        isRevealed ? -SwipeToRevealLockActionLayout.actionWidth : 0
    }

    private var currentOffset: CGFloat {
        let proposed = revealOffset + dragTranslation
        // Only allow swiping left (to reveal) or back right (to close) —
        // never past fully open or back into a rightward overscroll.
        return min(0, max(-SwipeToRevealLockActionLayout.actionWidth, proposed))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            lockButton

            content()
                .background(AppTheme.Colors.Neutral.n900)
                .offset(x: currentOffset)
                // `.simultaneousGesture` (rather than `.gesture`) so this
                // doesn't steal the tap-to-focus/cursor-placement gesture
                // `ParagraphTextField`'s underlying `UITextView` needs — it
                // only recognizes a genuine horizontal drag, which that
                // doesn't.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            // Only react to a horizontal drag, so this
                            // doesn't fight the editor's own vertical
                            // scrolling or the text view's own touch
                            // handling.
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            dragTranslation = value.translation.width
                        }
                        .onEnded { value in
                            // Same axis-dominance check as `.onChanged` —
                            // without it, a mostly-vertical gesture (e.g.
                            // scrolling) that happened to clear the 16pt
                            // minimum distance could still flip
                            // `isRevealed` here based on a stale/diagonal
                            // translation even though `dragTranslation`
                            // was never updated for it. Still snap back to
                            // wherever it was before this gesture
                            // (`dragTranslation = 0`) so the row doesn't
                            // stay visually offset if it was horizontal for
                            // a moment earlier in the same gesture.
                            guard abs(value.translation.width) > abs(value.translation.height) else {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    dragTranslation = 0
                                }
                                return
                            }
                            let projected = revealOffset + value.translation.width
                            withAnimation(.easeOut(duration: 0.2)) {
                                isRevealed = projected < -SwipeToRevealLockActionLayout.actionWidth / 2
                                dragTranslation = 0
                            }
                        }
                )
                // While the lock button is showing, a plain tap anywhere
                // on the block closes it again — same as tapping away from
                // a `.swipeActions` row elsewhere in this app. Only added
                // while revealed, so it never competes with the text
                // view's own tap-to-place-cursor handling during normal
                // editing.
                .modifier(CloseOnTapIfRevealed(isRevealed: $isRevealed))
        }
        .clipped()
    }

    /// The "잠금" button itself, matching `SwipeAction_Lock`'s lock icon +
    /// label — a neutral gray fill (distinct from the destructive red used
    /// for folder/document delete) since locking a block isn't destructive.
    /// Fills the row's full (variable) height, like the system
    /// `.swipeActions` buttons used for the folder/document rows.
    private var lockButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                isRevealed = false
            }
            onLockTapped()
        } label: {
            VStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(AppTheme.Colors.Content.primary)

                Text("잠금")
                    .appTextStyle(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.Content.primary)
            }
            .frame(width: SwipeToRevealLockActionLayout.actionWidth)
            .frame(maxHeight: .infinity)
            .background(AppTheme.Colors.Neutral.n600)
        }
        .buttonStyle(.plain)
    }
}

/// Adds a tap-to-close gesture only while a `SwipeToRevealLockAction` row
/// is in its revealed state — never present otherwise, so it can't
/// intercept the normal tap-to-focus interaction on the block content
/// underneath during regular editing.
private struct CloseOnTapIfRevealed: ViewModifier {
    @Binding var isRevealed: Bool

    func body(content: Content) -> some View {
        if isRevealed {
            content.onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) {
                    isRevealed = false
                }
            }
        } else {
            content
        }
    }
}

#Preview {
    NavigationStack {
        DetailView(document: Document(title: "오늘의 일기"))
    }
}
