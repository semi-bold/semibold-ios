import SwiftUI

/// Name-entry sheet for the "편집" swipe action on a folder row
/// (`Planning_9_SwipeActionFlow`, NO-003 §3.2).
///
/// Mirrors `NewFolderSheet`'s structure — a name field, inline error,
/// Cancel/Save toolbar actions — but pre-fills the folder's current name
/// and saves over it instead of creating a new folder.
struct RenameFolderSheet: View {
    @State private var viewModel: RenameFolderViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFieldFocused: Bool

    /// Called with the renamed folder once it's saved, so the presenter
    /// can refresh its list.
    let onRename: (Folder) -> Void

    init(folder: Folder, onRename: @escaping (Folder) -> Void) {
        _viewModel = State(initialValue: RenameFolderViewModel(folder: folder))
        self.onRename = onRename
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                TextField("Folder name", text: $viewModel.name)
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.text1)
                    .padding(AppTheme.Spacing.md)
                    .background(
                        AppTheme.Colors.surface2,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    )
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onChange(of: viewModel.name) {
                        viewModel.nameDidChange()
                    }
                    .onSubmit {
                        renameFolder()
                    }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .appTextStyle(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.error)
                }

                Spacer()
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.background)
            .navigationTitle("Rename Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.Colors.primary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        renameFolder()
                    }
                    .foregroundStyle(AppTheme.Colors.primary)
                    .disabled(!viewModel.canSave)
                }
            }
            .onAppear {
                nameFieldFocused = true
            }
        }
    }

    /// Validates and saves the renamed folder. On success, hands the
    /// updated folder back to the presenter and dismisses; on failure,
    /// the view-model's `errorMessage` is shown and the sheet stays open.
    private func renameFolder() {
        guard let updated = viewModel.renameFolder() else { return }
        onRename(updated)
        dismiss()
    }
}

#Preview {
    RenameFolderSheet(folder: Folder(name: "일상")) { _ in }
}
