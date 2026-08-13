import SwiftUI

/// The Slash Command bottom sheet (`tasks/NO-001.md` §12.2 "Slash Command는
/// bottom sheet 가능", §13.1 "/: Slash Command 열기").
///
/// Presented from `DetailScreen` when the user types a lone `/` into an empty
/// paragraph block. Lists every block type the editor supports other than
/// plain paragraph (the default every block starts as) — tapping one
/// converts the current block to that type via
/// `DetailViewModel.convertBlock(_:toSlashCommandOption:)` and dismisses
/// the sheet.
///
/// No `Screen_*`/`Planning_N_*Flow` artboard defines this menu's visual
/// layout — `sketch-autokit` doesn't have a dedicated "slash command menu"
/// component (CLAUDE.md §0 step 3). This reuses `atoms.py`'s `doc_row`
/// list-row language (leading icon, label, row divider) with `AppTheme`
/// tokens, presented at `.medium`/`.large` detents like a standard iOS
/// action sheet.
struct SlashCommandSheet: View {
    /// Called when the user taps an option. `DetailScreen` converts the
    /// current block and the sheet is dismissed by `DetailScreen` clearing
    /// `slashCommandBlockId`.
    let onSelect: (SlashCommandOption) -> Void

    var body: some View {
        NavigationStack {
            List(SlashCommandOption.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: option.iconName)
                            .foregroundStyle(AppTheme.Colors.Content.secondary)
                            .frame(width: AppTheme.Spacing.lg)

                        Text(option.title)
                            .appTextStyle(AppTheme.Typography.body)
                            .foregroundStyle(AppTheme.Colors.Content.primary)

                        Spacer()
                    }
                }
                .listRowBackground(AppTheme.Colors.Neutral.n900)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.Neutral.n900)
            .navigationTitle("Turn into")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    SlashCommandSheet { _ in }
}
