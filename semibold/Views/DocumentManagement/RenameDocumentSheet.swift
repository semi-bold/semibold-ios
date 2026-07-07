import SwiftUI

/// Title-entry sheet for the "편집" swipe action on a document row
/// (`Planning_9_SwipeActionFlow`, NO-003 §3.2).
///
/// Mirrors `NewDocumentSheet`'s structure — a title field, Cancel/Save
/// toolbar actions, blank-is-fine ("Untitled") handling — but pre-fills
/// the document's current title and saves over it instead of creating a
/// new document.
struct RenameDocumentSheet: View {
    @State private var viewModel: RenameDocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFieldFocused: Bool

    /// Called with the renamed document once it's saved, so the
    /// presenter can refresh its list.
    let onRename: (Document) -> Void

    init(document: Document, onRename: @escaping (Document) -> Void) {
        _viewModel = State(initialValue: RenameDocumentViewModel(document: document))
        self.onRename = onRename
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                TextField("Untitled", text: $viewModel.title)
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.Content.primary)
                    .padding(AppTheme.Spacing.md)
                    .background(
                        AppTheme.Colors.Neutral.n700,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    )
                    .focused($titleFieldFocused)
                    .submitLabel(.done)
                    .onChange(of: viewModel.title) {
                        viewModel.titleDidChange()
                    }
                    .onSubmit {
                        renameDocument()
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
            .navigationTitle("Rename Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.Colors.accent)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        renameDocument()
                    }
                    .foregroundStyle(AppTheme.Colors.accent)
                }
            }
            .onAppear {
                titleFieldFocused = true
            }
        }
    }

    /// Saves the renamed document. On success, hands it back to the
    /// presenter and dismisses; on failure, the view-model's
    /// `errorMessage` is shown and the sheet stays open so the user can
    /// retry.
    private func renameDocument() {
        guard let updated = viewModel.renameDocument() else { return }
        onRename(updated)
        dismiss()
    }
}

#Preview {
    RenameDocumentSheet(document: Document(title: "오늘의 일기")) { _ in }
}
