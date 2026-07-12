import SwiftUI

/// Name-entry sheet for the "new folder" step of
/// `Planning_2_FolderCreateFlow` (PLANNING §5.2).
///
/// Presented after the user picks "New Folder" from the "+" menu on
/// `HomeView`. Lets them type a name, shows an inline error if it's
/// invalid, and creates the folder on confirm.
struct NewFolderSheet: View {
    @State private var viewModel: NewFolderViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFieldFocused: Bool

    /// Called with the newly created folder once it's saved, so the
    /// presenter can refresh its list and select it
    /// (PLANNING §5.2: "폴더 목록 갱신" → "생성된 폴더 선택 상태로 전환").
    let onCreate: (Folder) -> Void

    init(parentId: String? = nil, onCreate: @escaping (Folder) -> Void) {
        _viewModel = State(initialValue: NewFolderViewModel(parentId: parentId))
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                TextField("Folder name", text: $viewModel.name)
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.Content.primary)
                    .padding(AppTheme.Spacing.md)
                    .background(
                        AppTheme.Colors.Neutral.n700,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    )
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onChange(of: viewModel.name) {
                        viewModel.nameDidChange()
                    }
                    .onSubmit {
                        createFolder()
                    }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .appTextStyle(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.Feedback.error)
                }

                Spacer()
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.Neutral.n900)
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.Colors.accent)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createFolder()
                    }
                    .foregroundStyle(AppTheme.Colors.accent)
                    .disabled(!viewModel.canCreate)
                }
            }
            .onAppear {
                nameFieldFocused = true
            }
        }
    }

    /// Validates and saves the folder. On success, hands the created
    /// folder back to the presenter and dismisses; on failure, the
    /// view-model's `errorMessage` is shown and the sheet stays open
    /// (PLANNING §5.2: "이름 유효?" → "아니오" → "에러 표시" → back to name
    /// entry).
    private func createFolder() {
        guard let created = viewModel.createFolder() else { return }
        onCreate(created)
        dismiss()
    }
}

#Preview {
    NewFolderSheet { _ in }
}
