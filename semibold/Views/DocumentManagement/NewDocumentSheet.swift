import SwiftUI

/// Title-entry sheet for the "new document" step of
/// `Planning_3_DocumentCreateFlow` (PLANNING §5.3).
///
/// Presented after the user picks "New Document" from the "+" menu on
/// `HomeView`. Lets them type a title — leaving it blank is fine, the
/// document is saved as "Untitled" (PLANNING §6.2) — and creates the
/// document on confirm.
///
/// This stands in for callout ④ ("제목 입력 영역") of
/// `Planning_3_DocumentCreateFlow`, which in the full flow lives in the
/// document Editor (callouts ④/⑤, `iOS_Editor`). The Editor screen itself
/// is out of scope for this brief (`block-editor-phase3`), so the title is
/// collected here, before the `documents` row is created, rather than
/// inside an editor that doesn't exist yet.
struct NewDocumentSheet: View {
    @State private var viewModel: NewDocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFieldFocused: Bool

    /// Called with the newly created document once it's saved, so the
    /// presenter can refresh its list and select it — mirroring
    /// `Planning_2_FolderCreateFlow`'s "목록 갱신" → "선택 상태로 전환"
    /// steps for documents.
    let onCreate: (Document) -> Void

    init(folderId: String? = nil, onCreate: @escaping (Document) -> Void) {
        _viewModel = State(initialValue: NewDocumentViewModel(folderId: folderId))
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                TextField("Untitled", text: $viewModel.title)
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.text1)
                    .padding(AppTheme.Spacing.md)
                    .background(
                        AppTheme.Colors.surface2,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    )
                    .focused($titleFieldFocused)
                    .submitLabel(.done)
                    .onChange(of: viewModel.title) {
                        viewModel.titleDidChange()
                    }
                    .onSubmit {
                        createDocument()
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
            .navigationTitle("New Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.Colors.primary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createDocument()
                    }
                    .foregroundStyle(AppTheme.Colors.primary)
                }
            }
            .onAppear {
                titleFieldFocused = true
            }
        }
    }

    /// Saves the document. On success, hands it back to the presenter and
    /// dismisses; on failure, the view-model's `errorMessage` is shown and
    /// the sheet stays open so the user can retry.
    private func createDocument() {
        guard let created = viewModel.createDocument() else { return }
        onCreate(created)
        dismiss()
    }
}

#Preview {
    NewDocumentSheet { _ in }
}
