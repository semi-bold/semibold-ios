import SwiftUI

/// The screen shown after tapping into a folder: that folder's nested
/// folders and documents.
///
/// Matches the `iOS_FolderContents` wireframe
/// (`sketch-autokit/screens/wireframe.py`) — a navigation bar with a
/// "< Semi:bold" back label, the current folder's name as the centered
/// title, and a "+" button, followed by a "하위 폴더" (nested folders)
/// section and a "문서" (documents) section listing everything directly
/// inside this folder.
///
/// Per `Planning_6_FolderNavigationFlow` (NO-003 §3.1), tapping a nested
/// folder row pushes this same screen again for that folder (callout
/// ④) — wired below via `NavigationLink(value:)`, resolved by the
/// `.navigationDestination(for: Folder.self)` registered once at the
/// `NavigationStack` root in `HomeView`. Tapping a document row pushes
/// `DetailView` (callout ⑤) — also wired via `NavigationLink(value:)`,
/// resolved by the `.navigationDestination(for: Document.self)`
/// registered alongside it at that same stack root.
struct FolderContentsView: View {
    @State private var viewModel: FolderContentsViewModel
    @Environment(\.dismiss) private var dismiss

    /// Whether the "+" menu (`iOS_AddMenu`) is showing, offering "New
    /// Folder" / "New Document" / "Cancel" — same pattern as `HomeView`,
    /// but scoped to this folder (`Planning_6_FolderNavigationFlow`
    /// callout ③).
    @State private var isAddMenuPresented = false

    /// Whether the new-folder name-entry sheet is showing
    /// (`Planning_2_FolderCreateFlow`, PLANNING §5.2), creating the
    /// folder as a child of this folder.
    @State private var isNewFolderSheetPresented = false

    /// Whether the new-document title-entry sheet is showing
    /// (`Planning_3_DocumentCreateFlow`, PLANNING §5.3), creating the
    /// document inside this folder.
    @State private var isNewDocumentSheetPresented = false

    /// The nested folder or document currently being renamed via the
    /// "편집" swipe action (`Planning_9_SwipeActionFlow`), or `nil` when
    /// no rename sheet is showing.
    @State private var entryBeingRenamed: Entry?

    /// The nested folder or document pending confirmation from the
    /// "삭제" swipe action, or `nil` when no delete-confirmation alert is
    /// showing (`Planning_9_SwipeActionFlow` callout ③).
    @State private var entryPendingDelete: Entry?

    init(folder: Folder) {
        _viewModel = State(initialValue: FolderContentsViewModel(folder: folder))
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            List {
                folderSection(
                    folders: viewModel.folders,
                    emptyText: "하위 폴더가 없습니다.",
                    onEdit: { entryBeingRenamed = .folder($0) },
                    onDelete: { entryPendingDelete = .folder($0) }
                )
                documentSection(
                    documents: viewModel.documents,
                    emptyText: "이 폴더에 문서가 없습니다.",
                    onEdit: { entryBeingRenamed = .document($0) },
                    onDelete: { entryPendingDelete = .document($0) }
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(AppTheme.Colors.Neutral.n900)
        .toolbar(.hidden)
        .onAppear {
            viewModel.load()
        }
        .confirmationDialog("Add", isPresented: $isAddMenuPresented, titleVisibility: .hidden) {
            Button("New Folder") {
                isNewFolderSheetPresented = true
            }
            Button("New Document") {
                isNewDocumentSheetPresented = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isNewFolderSheetPresented) {
            NewFolderSheet(parentId: viewModel.folder.id) { _ in
                viewModel.didCreateFolder()
            }
        }
        .sheet(isPresented: $isNewDocumentSheetPresented) {
            NewDocumentSheet(folderId: viewModel.folder.id) { _ in
                viewModel.didCreateDocument()
            }
        }
        .sheet(item: $entryBeingRenamed) { entry in
            switch entry {
            case .folder(let folder):
                RenameFolderSheet(folder: folder) { _ in
                    viewModel.didEditFolder()
                }
            case .document(let document):
                RenameDocumentSheet(document: document) { _ in
                    viewModel.didEditDocument()
                }
            }
        }
        .alert(
            AppConfirmationMessages.deleteTitle,
            isPresented: entryDeleteConfirmationPresented,
            presenting: entryPendingDelete
        ) { entry in
            Button(AppConfirmationMessages.confirmButton, role: .destructive) {
                switch entry {
                case .folder(let folder):
                    viewModel.deleteFolder(folder)
                case .document(let document):
                    viewModel.deleteDocument(document)
                }
            }
            Button(AppConfirmationMessages.cancelButton, role: .cancel) {}
        } message: { entry in
            switch entry {
            case .folder(let folder):
                // "삭제" swipe action — a folder with live nested content
                // gets the stronger warning so deleting it isn't a
                // surprise (`Planning_9_SwipeActionFlow` callout ③).
                Text(
                    viewModel.folderHasNestedContent(folder)
                        ? AppConfirmationMessages.deleteFolderWithContents
                        : AppConfirmationMessages.deleteSimple
                )
            case .document:
                Text(AppConfirmationMessages.deleteSimple)
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
            // §15.2 "삭제 실패" — shown when a folder/document delete
            // couldn't be persisted.
            Text(message)
        }
    }

    /// Whether the "삭제" swipe action's confirmation alert is showing —
    /// driven by `entryPendingDelete`.
    private var entryDeleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { entryPendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    entryPendingDelete = nil
                }
            }
        )
    }

    /// Whether the §15.2 delete-failure alert is shown — driven by
    /// `viewModel.errorMessage`. Dismissing it (the "OK" button, or
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

    // MARK: - Navigation bar

    /// Top bar: a back label pointing at the previous screen, the
    /// current folder's name as the centered title, and the add (+)
    /// button that will start the new folder/document flows scoped to
    /// this folder.
    private var navBar: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(viewModel.folder.name)
                    .appTextStyle(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.Content.primary)

                HStack {
                    backButton
                    Spacer()
                    addButton
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 52)

            Rectangle()
                .fill(AppTheme.Colors.Stroke.divider)
                .frame(height: 1)
        }
        .background(AppTheme.Colors.Neutral.n800)
    }

    /// Returns to the previous screen in the navigation stack
    /// (`Planning_6_FolderNavigationFlow` callout ①). `NavigationStack`
    /// already supplies the system back gesture/button; this label just
    /// matches the wireframe's literal text since the system back button
    /// is hidden along with the rest of the nav bar (`.toolbar(.hidden)`).
    ///
    /// Reads "< Semi:bold" for a root-level folder (going back to
    /// `HomeView`), or "< <상위 폴더명>" for a nested folder (going back
    /// to the parent folder's own `FolderContentsView`) — "하위 폴더
    /// 진입 시 레이블은 상위 폴더명으로 바뀐다".
    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Text(viewModel.backButtonLabel.text)
                .appTextStyle(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.accent)
        }
    }

    /// Entry point for the "new folder / new document" menu, scoped to
    /// this folder (`Planning_6_FolderNavigationFlow` callout ③).
    private var addButton: some View {
        Button {
            isAddMenuPresented = true
        } label: {
            Image(systemName: "plus")
                .appTextStyle(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.Content.primary)
                .frame(width: 24, height: 24)
        }
    }

}

#Preview {
    NavigationStack {
        FolderContentsView(folder: Folder(name: "일상"))
    }
}
