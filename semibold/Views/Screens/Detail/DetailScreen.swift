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
struct DetailScreen: View {
    @State private var viewModel: DetailViewModel
    @FocusState private var focusedBlockId: String?
    @State private var cursorOffsetToApply: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Whether the navigation drawer (`icon_menu` in
    /// `Planning_Nav_1_TopBarFlow`) is showing — presented via
    /// `SidebarDrawerView`, `03-sidebar-drawer`'s search-first drawer
    /// (`Planning_Nav_2_DrawerFlow`).
    @State private var isDrawerPresented = false

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
        .overlay {
            // This screen is itself a pushed `Document.self` destination
            // registered once at `HomeScreen`'s `NavigationStack` root — the
            // drawer's search-result rows push through that same
            // registration, the same way `HomeScreen`/`FolderContentsScreen`'s
            // own `FolderRow`/`DocumentRow` rows do (`SidebarDrawerView`'s
            // doc comment).
            SidebarDrawerView(isPresented: $isDrawerPresented)
        }
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
    /// opened from — `HomeScreen`'s document list for a root-level document,
    /// or the owning `FolderContentsScreen` for one filed inside a folder.
    /// Icon-only (a house for root, a chevron for a nested folder), the
    /// same as `FolderContentsScreen`'s back button
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
    ///
    /// A menu (hamburger) button joins it in the trailing group as of
    /// `Planning_Nav_1_TopBarFlow` (FLOW-NAV-001) — this NavBar previously
    /// had no trailing element besides `exportShareLink`; same trailing
    /// inset/spacing as `HomeScreen`/`FolderContentsScreen` use for their own
    /// menu buttons.
    private var navBar: some View {
        NavBar(
            leading: {
                Button {
                    dismiss()
                } label: {
                    BackButtonIcon(label: viewModel.backButtonLabel)
                }
                .accessibilityLabel(viewModel.backButtonLabel.accessibilityLabel)
            },
            trailingExtra: { exportShareLink },
            onMenuTapped: {
                isDrawerPresented = true
            }
        )
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
                    blockRow(for: item, content: viewModel.textContent(forItemId: item.id))
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

    /// Routes a block to the per-kind factory matching `content.textKind`
    /// — `TextItemKind`'s 8 recognized kinds each get their own
    /// `Views/Components/Block/*BlockView.chrome(...)` call, all
    /// returning `BlockRowChrome` directly (not a per-kind `View` struct)
    /// so every case of this switch produces the same concrete type. That
    /// uniformity is what lets a block's `content.textKind` change (e.g.
    /// backspacing an empty list item back to a paragraph,
    /// `DetailViewModel.exitEmptyListItem`) without SwiftUI tearing down
    /// and rebuilding the `ParagraphTextField` underneath — see
    /// `BlockRowChrome`'s doc comment. Anything not explicitly listed (a
    /// fresh block, or a `content.textKind` this build doesn't recognize
    /// — `TextItemKind.unknown`) falls back to `ParagraphBlockView`, the
    /// same way the pre-split `BlockRow` rendered those with no marker
    /// and `.body` typography.
    private func blockRow(for item: DocumentItem, content: TextContent) -> BlockRowChrome {
        switch content.textKind {
        case TextItemKind.heading:
            HeadingBlockView.chrome(
                item: item,
                content: content,
                focusedBlockId: $focusedBlockId,
                cursorOffsetToApply: $cursorOffsetToApply,
                onTextChange: { text in viewModel.updateBlockText(item.id, text: text) },
                onEnter: { text, cursorOffset in
                    viewModel.insertBlock(after: item.id, currentText: text, cursorOffset: cursorOffset)
                },
                onBackspaceAtStart: { text in viewModel.mergeOrDeleteBlock(item.id, currentText: text) }
            )
        case TextItemKind.quote:
            QuoteBlockView.chrome(
                item: item,
                content: content,
                focusedBlockId: $focusedBlockId,
                cursorOffsetToApply: $cursorOffsetToApply,
                onTextChange: { text in viewModel.updateBlockText(item.id, text: text) },
                onEnter: { text, cursorOffset in
                    viewModel.insertBlock(after: item.id, currentText: text, cursorOffset: cursorOffset)
                },
                onBackspaceAtStart: { text in viewModel.mergeOrDeleteBlock(item.id, currentText: text) }
            )
        case TextItemKind.checklist:
            ChecklistBlockView.chrome(
                item: item,
                content: content,
                focusedBlockId: $focusedBlockId,
                cursorOffsetToApply: $cursorOffsetToApply,
                onTextChange: { text in viewModel.updateBlockText(item.id, text: text) },
                onEnter: { text, cursorOffset in
                    viewModel.insertBlock(after: item.id, currentText: text, cursorOffset: cursorOffset)
                },
                onBackspaceAtStart: { text in viewModel.mergeOrDeleteBlock(item.id, currentText: text) },
                onToggleChecklist: { viewModel.toggleChecklistItem(blockId: item.id) }
            )
        case TextItemKind.bulletedListItem:
            BulletedListBlockView.chrome(
                item: item,
                content: content,
                focusedBlockId: $focusedBlockId,
                cursorOffsetToApply: $cursorOffsetToApply,
                onTextChange: { text in viewModel.updateBlockText(item.id, text: text) },
                onEnter: { text, cursorOffset in
                    viewModel.insertBlock(after: item.id, currentText: text, cursorOffset: cursorOffset)
                },
                onBackspaceAtStart: { text in viewModel.mergeOrDeleteBlock(item.id, currentText: text) }
            )
        case TextItemKind.numberedListItem:
            NumberedListBlockView.chrome(
                item: item,
                content: content,
                numberedListNumber: viewModel.numberedListNumber(forItemId: item.id),
                focusedBlockId: $focusedBlockId,
                cursorOffsetToApply: $cursorOffsetToApply,
                onTextChange: { text in viewModel.updateBlockText(item.id, text: text) },
                onEnter: { text, cursorOffset in
                    viewModel.insertBlock(after: item.id, currentText: text, cursorOffset: cursorOffset)
                },
                onBackspaceAtStart: { text in viewModel.mergeOrDeleteBlock(item.id, currentText: text) }
            )
        case TextItemKind.codeBlock:
            CodeBlockView.chrome(
                item: item,
                content: content,
                focusedBlockId: $focusedBlockId,
                cursorOffsetToApply: $cursorOffsetToApply,
                onTextChange: { text in viewModel.updateBlockText(item.id, text: text) },
                onEnter: { text, cursorOffset in
                    viewModel.insertBlock(after: item.id, currentText: text, cursorOffset: cursorOffset)
                },
                onBackspaceAtStart: { text in viewModel.mergeOrDeleteBlock(item.id, currentText: text) }
            )
        case TextItemKind.divider:
            DividerBlockView.chrome(
                item: item,
                content: content,
                focusedBlockId: $focusedBlockId,
                cursorOffsetToApply: $cursorOffsetToApply,
                onTextChange: { text in viewModel.updateBlockText(item.id, text: text) },
                onEnter: { text, cursorOffset in
                    viewModel.insertBlock(after: item.id, currentText: text, cursorOffset: cursorOffset)
                },
                onBackspaceAtStart: { text in viewModel.mergeOrDeleteBlock(item.id, currentText: text) }
            )
        default:
            ParagraphBlockView.chrome(
                item: item,
                content: content,
                focusedBlockId: $focusedBlockId,
                cursorOffsetToApply: $cursorOffsetToApply,
                onTextChange: { text in viewModel.updateBlockText(item.id, text: text) },
                onEnter: { text, cursorOffset in
                    viewModel.insertBlock(after: item.id, currentText: text, cursorOffset: cursorOffset)
                },
                onBackspaceAtStart: { text in viewModel.mergeOrDeleteBlock(item.id, currentText: text) }
            )
        }
    }
}

#Preview {
    NavigationStack {
        DetailScreen(document: Document(title: "오늘의 일기"))
    }
    .environment(AccountActionCenter())
}
