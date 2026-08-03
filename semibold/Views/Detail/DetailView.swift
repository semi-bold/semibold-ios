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
        .onChange(of: viewModel.blockIdToDefocus) { _, newValue in
            guard let newValue else { return }
            if focusedBlockId == newValue {
                focusedBlockId = nil
            }
            viewModel.defocusHandled()
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
    /// or the owning `FolderContentsView` for one filed inside a folder.
    /// Icon-only (a house for root, a chevron for a nested folder), the
    /// same as `FolderContentsView`'s back button
    /// (`viewModel.backButtonLabel`, mirroring
    /// `Planning_6_FolderNavigationFlow` callout ①) — the destination
    /// folder's name isn't shown as text here either, so it can't break
    /// the NavBar's layout however long it is.
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
                    BackButtonIcon(label: viewModel.backButtonLabel)
                }
                .accessibilityLabel(viewModel.backButtonLabel.accessibilityLabel)

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
            // The top padding is breathing room below the title area's
            // divider line, above the first block only — each block row's
            // own vertical padding (`AppTheme.Spacing.sm`) already governs
            // the gap *between* blocks, so this doesn't affect that.
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
                        }
                    )
                }
            }
            .padding(.top, AppTheme.Spacing.md)
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
    ///
    /// Top padding is `blockList`'s `LazyVStack` top padding plus the
    /// block row's own vertical padding, matching where that (only) empty
    /// block's text actually sits — this overlay is positioned relative to
    /// `blockList`/`ScrollView`, not the `LazyVStack` itself.
    private var emptyContentPlaceholder: some View {
        Text("Markdown으로 작성하거나 / 를 눌러 블록을 추가하세요.")
            .appTextStyle(AppTheme.Typography.body)
            .foregroundStyle(AppTheme.Colors.Content.secondary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.md + AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.sm)
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
/// item's `TextContent` (`content` — the actual text). `content.textKind`
/// is compared against `TextItemKind`'s constants rather than a closed
/// enum — see `DetailViewModel.swift`'s `TextItemKind` doc comment.
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
        onToggleChecklist: @escaping () -> Void
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

    /// Whether this row is currently showing the rendered `---` rule
    /// rather than its editable text — a divider that isn't focused.
    private var showsDividerRule: Bool {
        isDivider && focusedBlockId.wrappedValue != item.id
    }

    /// Always renders `editableBody` — critically, this means the
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
    /// on top (`editableBody`) reuses the exact same always-present
    /// mechanism every other block type already focuses reliably.
    var body: some View {
        editableBody
    }

    private var editableBody: some View {
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

                ZStack(alignment: .leading) {
                    // Always hit-testable, even while the divider rule is
                    // drawn on top of it (`showsDividerRule`) — so a tap
                    // anywhere on the row reaches this real `UITextView`
                    // directly and focuses it through the ordinary native
                    // UIKit path (touch → `becomeFirstResponder()` →
                    // `.focused()` observes the change), the exact same
                    // reliable mechanism every other block type already
                    // uses. An earlier version instead drove focus the
                    // other way — a `.onTapGesture` on the rule overlay
                    // imperatively pushed `focusedBlockId` and relied on
                    // SwiftUI's `.focused()` bridge to call
                    // `becomeFirstResponder()` on this view in response —
                    // which is the fragile direction: the request could be
                    // dropped when it landed in the same transaction as
                    // this view's own opacity/hit-testing change, so the
                    // first tap only flipped state and a second, genuinely
                    // native tap was needed to actually focus it.
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
                    .opacity(showsDividerRule ? 0 : 1)

                    // A divider block's `"---"` text field sits underneath
                    // this rule whenever it isn't focused. Purely a visual
                    // overlay — `allowsHitTesting(false)` lets every tap
                    // pass straight through to the text field above, which
                    // reveals the literal `"---"` for editing/deleting once
                    // it's focused (see that field's comment for why taps
                    // aren't handled here instead).
                    Rectangle()
                        .fill(AppTheme.Colors.Stroke.border)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(showsDividerRule ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, showsDividerRule ? AppTheme.Spacing.lg : AppTheme.Spacing.sm)
        .background(isCodeBlock ? AppTheme.Colors.Neutral.n700 : AppTheme.Colors.Neutral.n900)
    }
}

#Preview {
    NavigationStack {
        DetailView(document: Document(title: "오늘의 일기"))
    }
}
