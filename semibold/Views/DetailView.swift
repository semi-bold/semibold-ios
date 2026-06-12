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
/// there (PLANNING §5.4/§13.1). Block-type conversions, delete/merge, and
/// reorder (`Planning_4_BlockCreateFlow` callouts ①③⑤) land in later
/// acceptance criteria — every block is a plain paragraph for now.
struct DetailView: View {
    @State private var viewModel: DetailViewModel
    @FocusState private var focusedBlockId: String?
    @Environment(\.dismiss) private var dismiss

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
            viewModel.focusHandled()
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
                        onTextChange: { text in
                            viewModel.updateBlockText(block.id, text: text)
                        },
                        onEnter: { text, cursorOffset in
                            viewModel.insertBlock(after: block.id, currentText: text, cursorOffset: cursorOffset)
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
/// Block-type-specific styling (headings, lists, checklists, quotes,
/// code) is `markdown-phase4` scope — this row renders every block as a
/// plain paragraph input for now.
private struct BlockRow: View {
    let block: DocumentBlock
    var focusedBlockId: FocusState<String?>.Binding
    let onTextChange: (String) -> Void
    let onEnter: (String, Int) -> Void

    @State private var text: String

    init(
        block: DocumentBlock,
        focusedBlockId: FocusState<String?>.Binding,
        onTextChange: @escaping (String) -> Void,
        onEnter: @escaping (String, Int) -> Void
    ) {
        self.block = block
        self.focusedBlockId = focusedBlockId
        self.onTextChange = onTextChange
        self.onEnter = onEnter
        _text = State(initialValue: block.markdownSource ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ParagraphTextField(
                text: $text,
                onTextChange: onTextChange,
                onEnter: { cursorOffset in
                    onEnter(text, cursorOffset)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md)
            .focused(focusedBlockId, equals: block.id)

            Rectangle()
                .fill(AppTheme.Colors.divider)
                .frame(height: 1)
        }
        .background(AppTheme.Colors.background)
    }
}

#Preview {
    NavigationStack {
        DetailView(document: Document(title: "오늘의 일기"))
    }
}
