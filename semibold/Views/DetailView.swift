import SwiftUI

/// The document editor screen: a document's title, date, and its blocks.
///
/// Matches the `iOS_Editor` artboard (`../sketch-autokit/screens/wireframe.py`)
/// — the reference screen for `Planning_4_BlockCreateFlow` — with a nav
/// bar, a title area showing the document's title and last-updated date,
/// and a scrolling list of the document's blocks below a divider.
///
/// This view currently renders the document read-only (static layout +
/// existing blocks). Paragraph input, Enter-to-create, delete/merge, and
/// reorder (`Planning_4_BlockCreateFlow` callouts ①–⑤, PLANNING §5.4/§6.3)
/// land in a later acceptance criterion.
struct DetailView: View {
    @State private var viewModel: DetailViewModel
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
    /// `Block_*` rows. A document with no blocks yet shows a placeholder
    /// hint instead — creating the first empty block to type into is
    /// AC2's scope (Enter-to-create / first block on open).
    private var blockList: some View {
        Group {
            if viewModel.blocks.isEmpty {
                emptyBlockPlaceholder
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.blocks) { block in
                            BlockRow(block: block)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.background)
    }

    /// Shown when the document has no blocks yet — a lightweight hint
    /// where the first block will appear once typing starts (AC2).
    private var emptyBlockPlaceholder: some View {
        Text("Start writing…")
            .appTextStyle(AppTheme.Typography.body)
            .foregroundStyle(AppTheme.Colors.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.md)
    }
}

/// A single read-only block row, matching the wireframe's `Block_*`
/// groups: the block's text content with a divider below.
///
/// Block-type-specific styling (headings, lists, checklists, quotes,
/// code) is `markdown-phase4` scope — this row renders every block as
/// plain text for now.
private struct BlockRow: View {
    let block: DocumentBlock

    var body: some View {
        VStack(spacing: 0) {
            Text(block.markdownSource ?? "")
                .appTextStyle(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.md)

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
