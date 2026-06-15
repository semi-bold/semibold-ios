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
                .fill(AppTheme.Colors.divider)
                .frame(height: 1)

            blockList
        }
        .background(AppTheme.Colors.background)
        .navigationBarBackButtonHidden()
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
    }

    // MARK: - Nav bar

    /// Top bar with a back button to return to `HomeView`'s document list.
    ///
    /// The wireframe also shows a "잠금" (lock) button on the right
    /// (`DocLockBtn`) — that's Secret Lock, explicitly out of this
    /// planning's scope (callout ④ of `Planning_4_BlockCreateFlow`,
    /// PLANNING §1.2), so it's omitted here.
    private var navBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("< Back")
                        .appTextStyle(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.primary)
                }

                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 52)

            Rectangle()
                .fill(AppTheme.Colors.divider)
                .frame(height: 1)
        }
        .background(AppTheme.Colors.surface)
    }

    // MARK: - Title area

    /// Document title and last-updated date, matching `TitleArea` in the
    /// wireframe.
    private var titleArea: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(viewModel.document.title)
                .appTextStyle(AppTheme.Typography.heading2)
                .foregroundStyle(AppTheme.Colors.text1)

            Text(viewModel.document.updatedAt.formatted(date: .numeric, time: .omitted))
                .appTextStyle(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.sm)
        .frame(height: 72, alignment: .topLeading)
        .background(AppTheme.Colors.background)
    }

    // MARK: - Block list

    /// The document's blocks, matching the wireframe's stacked
    /// `Block_*` rows — each one an editable paragraph input
    /// (callout ②). `load()` guarantees at least one (empty) block exists,
    /// so this list is never empty by the time it's shown.
    private var blockList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.blocks) { block in
                    BlockRow(
                        block: block,
                        focusedBlockId: $focusedBlockId,
                        cursorOffsetToApply: $cursorOffsetToApply,
                        onTextChange: { text in
                            viewModel.updateBlockText(block.id, text: text)
                        },
                        onEnter: { text, cursorOffset in
                            viewModel.insertBlock(after: block.id, currentText: text, cursorOffset: cursorOffset)
                        },
                        onBackspaceAtStart: { text in
                            viewModel.mergeOrDeleteBlock(block.id, currentText: text)
                        },
                        onToggleChecklist: {
                            viewModel.toggleChecklistItem(blockId: block.id)
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.background)
    }
}

/// A single editable block row, matching the wireframe's `Block_*` groups:
/// a text input for the block's content with a divider below
/// (`Block_Editing`'s cursor when focused — callout ②).
///
/// `.bulletedListItem`/`.numberedListItem` blocks show a `•`/`<n>.` marker
/// before the editable text (§7.1/§7.3's `- item` / `1. item` syntax).
/// `.checklistItem` blocks show a tappable checkbox in that same leading
/// column — tapping it toggles the task's done/not-done state (§7.1).
/// `.blockquote` blocks show a vertical rule in that same leading column and
/// dim the quoted text, marking it as a quote (§7.1/§7.3's `> quote`
/// syntax). Code-block styling is still `markdown-phase4` follow-up scope —
/// that block type renders as a plain paragraph input for now.
private struct BlockRow: View {
    let block: DocumentBlock
    var focusedBlockId: FocusState<String?>.Binding
    @Binding var cursorOffsetToApply: Int?
    let onTextChange: (String) -> Void
    let onEnter: (String, Int) -> Void
    let onBackspaceAtStart: (String) -> Void
    let onToggleChecklist: () -> Void

    @State private var text: String

    init(
        block: DocumentBlock,
        focusedBlockId: FocusState<String?>.Binding,
        cursorOffsetToApply: Binding<Int?>,
        onTextChange: @escaping (String) -> Void,
        onEnter: @escaping (String, Int) -> Void,
        onBackspaceAtStart: @escaping (String) -> Void,
        onToggleChecklist: @escaping () -> Void
    ) {
        self.block = block
        self.focusedBlockId = focusedBlockId
        self._cursorOffsetToApply = cursorOffsetToApply
        self.onTextChange = onTextChange
        self.onEnter = onEnter
        self.onBackspaceAtStart = onBackspaceAtStart
        self.onToggleChecklist = onToggleChecklist
        _text = State(initialValue: block.displayText)
    }

    /// The typography this block's text is shown in — heading levels 1-3
    /// map to `AppTheme.Typography.heading1`/`.heading2`/`.heading3`
    /// (§7.1/§7.3's `# `/`## `/`### ` conversions); every other block type
    /// uses `.body`.
    private var textStyle: TextStyleToken {
        switch block.type {
        case .heading:
            switch block.headingLevel {
            case 1: return AppTheme.Typography.heading1
            case 2: return AppTheme.Typography.heading2
            default: return AppTheme.Typography.title
            }
        default:
            return AppTheme.Typography.body
        }
    }

    /// The marker shown before a list item's text — a bullet for
    /// `.bulletedListItem`, the item's number followed by a period for
    /// `.numberedListItem` (§7.1/§7.3's `- item` / `1. item` syntax). `nil`
    /// for every other block type, which shows no marker. `.checklistItem`
    /// blocks show a checkbox instead, and `.blockquote` blocks show a
    /// vertical rule, in the same leading column — see `body`.
    private var listMarker: String? {
        switch block.type {
        case .bulletedListItem: return "•"
        case .numberedListItem: return "\(block.numberedListNumber ?? 1)."
        default: return nil
        }
    }

    /// The color this block's text is shown in — `.blockquote` text is
    /// dimmed (`AppTheme.Colors.text2`) to read as a quote, distinct from
    /// the surrounding paragraph text; every other block type uses the
    /// primary text color.
    private var textColor: Color {
        block.type == .blockquote ? AppTheme.Colors.text2 : AppTheme.Colors.text1
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                if let listMarker {
                    Text(listMarker)
                        .appTextStyle(textStyle)
                        .foregroundStyle(AppTheme.Colors.text1)
                        .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
                } else if block.type == .checklistItem {
                    Button(action: onToggleChecklist) {
                        Image(systemName: block.isChecked ? "checkmark.square" : "square")
                            .foregroundStyle(block.isChecked ? AppTheme.Colors.primary : AppTheme.Colors.text2)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
                    .frame(height: textStyle.lineHeight, alignment: .center)
                } else if block.type == .blockquote {
                    Rectangle()
                        .fill(AppTheme.Colors.border)
                        .frame(width: AppTheme.Spacing.xs)
                        .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
                }

                ParagraphTextField(
                    text: $text,
                    textStyle: textStyle,
                    textColor: textColor,
                    onTextChange: onTextChange,
                    onEnter: { cursorOffset in
                        onEnter(text, cursorOffset)
                    },
                    onBackspaceAtStart: {
                        onBackspaceAtStart(text)
                    },
                    cursorOffsetToApply: focusedBlockId.wrappedValue == block.id ? $cursorOffsetToApply : .constant(nil)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused(focusedBlockId, equals: block.id)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md)

            Rectangle()
                .fill(AppTheme.Colors.divider)
                .frame(height: 1)
        }
        .background(AppTheme.Colors.background)
        .onChange(of: block.contentJSON) { _, _ in
            // Keep this row's text in sync when the view model changes
            // `block`'s content without the user typing here directly —
            // e.g. a later block's Backspace-at-start merge appends its
            // text onto the end of this block, or this same block just
            // converted from paragraph to heading (its displayed text
            // drops the `#` prefix).
            let newText = block.displayText
            if text != newText {
                text = newText
            }
        }
    }
}

#Preview {
    NavigationStack {
        DetailView(document: Document(title: "오늘의 일기"))
    }
}
