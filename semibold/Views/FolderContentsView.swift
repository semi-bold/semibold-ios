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

    /// The nested folder currently being renamed via the "편집" swipe
    /// action (`Planning_9_SwipeActionFlow`), or `nil` when no rename
    /// sheet is showing.
    @State private var folderBeingRenamed: Folder?

    /// The document currently being renamed via the "편집" swipe action,
    /// or `nil` when no rename sheet is showing.
    @State private var documentBeingRenamed: Document?

    init(folder: Folder) {
        _viewModel = State(initialValue: FolderContentsViewModel(folder: folder))
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            List {
                folderSection
                documentSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(AppTheme.Colors.background)
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
        .sheet(item: $folderBeingRenamed) { folder in
            RenameFolderSheet(folder: folder) { _ in
                viewModel.didEditFolder()
            }
        }
        .sheet(item: $documentBeingRenamed) { document in
            RenameDocumentSheet(document: document) { _ in
                viewModel.didEditDocument()
            }
        }
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
                    .foregroundStyle(AppTheme.Colors.text1)

                HStack {
                    backButton
                    Spacer()
                    addButton
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 52)

            Rectangle()
                .fill(AppTheme.Colors.divider)
                .frame(height: 1)
        }
        .background(AppTheme.Colors.surface)
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
                .foregroundStyle(AppTheme.Colors.primary)
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
                .foregroundStyle(AppTheme.Colors.text1)
                .frame(width: 24, height: 24)
        }
    }

    // MARK: - Nested folders section

    private var folderSection: some View {
        Section {
            if viewModel.folders.isEmpty {
                emptyRow(text: "하위 폴더가 없습니다.")
            } else {
                ForEach(viewModel.folders) { folder in
                    // Tapping a nested folder pushes this same screen
                    // again for that folder, recursing as deep as the
                    // tree goes (`Planning_6_FolderNavigationFlow`
                    // callout ④). The destination is registered once at
                    // the `NavigationStack` root in `HomeView`, so this
                    // push lands on the same stack as every other one.
                    NavigationLink(value: folder) {
                        // "편집" swipe action opens `RenameFolderSheet`
                        // (`Planning_9_SwipeActionFlow` callouts ①–③).
                        // "삭제" is still a no-op — soft-delete behavior is
                        // the next acceptance-criteria item of
                        // `.claude/features/02-swipe-actions.md`.
                        FolderRow(folder: folder, onEdit: { folderBeingRenamed = folder }, onDelete: {})
                    }
                }
            }
        } header: {
            sectionHeader("하위 폴더")
        }
    }

    // MARK: - Documents section

    private var documentSection: some View {
        Section {
            if viewModel.documents.isEmpty {
                emptyRow(text: "이 폴더에 문서가 없습니다.")
            } else {
                ForEach(viewModel.documents) { document in
                    // Tapping a document pushes `DetailView` for it
                    // (`Planning_6_FolderNavigationFlow` callout ⑤). The
                    // destination is registered once at the
                    // `NavigationStack` root in `HomeView`, so this push
                    // lands on the same stack as every other one.
                    NavigationLink(value: document) {
                        // "편집" swipe action opens `RenameDocumentSheet`
                        // (`Planning_9_SwipeActionFlow` callouts ①–③).
                        // "삭제" is still a no-op — soft-delete behavior is
                        // the next acceptance-criteria item of
                        // `.claude/features/02-swipe-actions.md`.
                        DocumentRow(document: document, onEdit: { documentBeingRenamed = document }, onDelete: {})
                    }
                }
            }
        } header: {
            sectionHeader("문서")
        }
    }
}

#Preview {
    NavigationStack {
        FolderContentsView(folder: Folder(name: "일상"))
    }
}
