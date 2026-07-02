import SwiftUI

/// The Private Layer's home screen: the top-level folder and document
/// list a user sees when they open the app.
///
/// Matches the `Screen_Home` wireframe (`iOS_PrivateSpace` artboard in
/// `sketch-autokit/screens/wireframe.py`) — a navigation bar showing the
/// current space ("Private") and an add button, followed by a "폴더"
/// (folders) section and a "문서" (documents) section listing everything
/// at the root of the user's document tree.
struct HomeView: View {
    /// Called when the user wants to return to OnboardingView — clears
    /// the Keychain session and transitions back to `.showOnboarding`.
    var onResetToOnboarding: (() -> Void)?

    @State private var viewModel = HomeViewModel()
    @State private var isResetConfirmationPresented = false

    /// Shared trigger point for the macOS "New Document"/"New Folder" menu
    /// commands (Cmd+N / Cmd+Shift+N, §13.2) — see `AppCommandCenter`.
    @Environment(AppCommandCenter.self) private var commandCenter

    /// Whether the "+" menu (`iOS_AddMenu`) is showing, offering "New
    /// Folder" / "New Document" / "Cancel" (callouts ④/⑤ of
    /// `Planning_2_FolderCreateFlow` / `Planning_3_DocumentCreateFlow`).
    @State private var isAddMenuPresented = false

    /// Whether the new-folder name-entry sheet is showing
    /// (`Planning_2_FolderCreateFlow`, PLANNING §5.2).
    @State private var isNewFolderSheetPresented = false

    /// Whether the new-document title-entry sheet is showing
    /// (`Planning_3_DocumentCreateFlow`, PLANNING §5.3).
    @State private var isNewDocumentSheetPresented = false

    /// The folder or document currently being renamed via the "편집" swipe
    /// action (`Planning_9_SwipeActionFlow`), or `nil` when no rename
    /// sheet is showing. Holding the `Entry` itself (rather than a
    /// separate `Bool`) lets the rename sheet pre-fill the right row's
    /// name.
    @State private var entryBeingRenamed: Entry?

    /// The folder or document pending confirmation from the "삭제" swipe
    /// action, or `nil` when no delete-confirmation alert is showing
    /// (`Planning_9_SwipeActionFlow` callout ③).
    @State private var entryPendingDelete: Entry?

    var body: some View {
        NavigationStack {
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
            .navigationDestination(for: Folder.self) { folder in
                // Registered once at the stack root so every push in the
                // chain — including the recursive pushes nested folders
                // make from inside `FolderContentsView` itself — resolves
                // through this same destination (`Planning_6_FolderNavigationFlow`
                // callout ④).
                FolderContentsView(folder: folder)
            }
            .navigationDestination(for: Document.self) { document in
                // Same reasoning as the `Folder.self` destination above —
                // registered once here so a document row tapped from this
                // screen or from any nested `FolderContentsView` resolves
                // through this same destination (`Planning_6_FolderNavigationFlow`
                // callout ⑤). This restores document-row navigation that a
                // since-merged debugging commit had stripped from `HomeView`
                // — not new functionality.
                DetailView(document: document)
            }
        }
        .onAppear {
            viewModel.load()
        }
        .onChange(of: commandCenter.newDocumentRequestCount) {
            // Cmd+N (§13.2) — open the same sheet as "+" → "New Document".
            isNewDocumentSheetPresented = true
        }
        .onChange(of: commandCenter.newFolderRequestCount) {
            // Cmd+Shift+N (§13.2) — open the same sheet as "+" → "New Folder".
            isNewFolderSheetPresented = true
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
            NewFolderSheet { _ in
                viewModel.didCreateFolder()
            }
        }
        .sheet(isPresented: $isNewDocumentSheetPresented) {
            NewDocumentSheet { _ in
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

    /// Top bar: app name, "Private" space badge, and the add (+) button
    /// that starts the new folder/document flows (Planning_2 /
    /// Planning_3).
    private var navBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text("Semi:bold")
                    .appTextStyle(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.text1)

                spaceBadge

                Spacer()

                if KeychainSessionStore().load()?.mode == .local {
                    switchAccountButton
                }

                addButton
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 52)

            Rectangle()
                .fill(AppTheme.Colors.divider)
                .frame(height: 1)
        }
        .background(AppTheme.Colors.surface)
    }

    /// "Private" badge — everything on this screen lives in the user's
    /// Private space (Secret-Lock items aren't distinguished yet).
    private var spaceBadge: some View {
        Text("Private")
            .appTextStyle(AppTheme.Typography.label)
            .foregroundStyle(AppTheme.Colors.primary)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(
                AppTheme.Colors.primary.opacity(0.15),
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.full)
            )
    }

    /// Appears in the nav bar when the current session is local-only.
    /// Lets the user return to OnboardingView to sign in with Apple.
    private var switchAccountButton: some View {
        Button {
            isResetConfirmationPresented = true
        } label: {
            Image(systemName: "person.circle")
                .appTextStyle(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.text2)
                .frame(width: 40, height: 40)
        }
        .confirmationDialog(
            "Apple 로그인으로 전환",
            isPresented: $isResetConfirmationPresented
        ) {
            Button("Apple로 로그인") {
                onResetToOnboarding?()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("로컬 데이터는 유지되며, Apple 로그인 이후에도 로컬로 이용을 선택하면 다시 돌아올 수 있습니다.")
        }
    }

    /// Entry point for the "new folder / new document" menu
    /// (`Planning_2_FolderCreateFlow` / `Planning_3_DocumentCreateFlow`,
    /// callout ① — "현재 보고 있는 위치를 기준으로 무언가를 새로 만들기
    /// 시작하는 단일 진입점").
    private var addButton: some View {
        Button {
            isAddMenuPresented = true
        } label: {
            Image(systemName: "plus")
                .appTextStyle(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.primary)
                .frame(width: 40, height: 40)
                .background(
                    AppTheme.Colors.primary.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                )
        }
    }

    // MARK: - Folders section

    private var folderSection: some View {
        Section {
            if viewModel.folders.isEmpty {
                // §15.1 "폴더가 없을 때" — encourages creating the first
                // folder via the "+" button in `navBar`.
                emptyRow(text: "첫 폴더를 만들어보세요.")
            } else {
                ForEach(viewModel.folders) { folder in
                    // Tapping a folder pushes `FolderContentsView` for it
                    // (`Planning_6_FolderNavigationFlow` callout ①);
                    // "편집"/"삭제" open `RenameFolderSheet`/a confirmation
                    // alert (`Planning_9_SwipeActionFlow` callouts ①–③).
                    // `FolderRow` itself wraps the `NavigationLink`.
                    FolderRow(
                        folder: folder,
                        onEdit: { entryBeingRenamed = .folder(folder) },
                        onDelete: { entryPendingDelete = .folder(folder) }
                    )
                }
            }
        } header: {
            sectionHeader("폴더")
        }
    }

    // MARK: - Documents section

    private var documentSection: some View {
        Section {
            if viewModel.documents.isEmpty {
                // §15.1 "문서가 없을 때" — root level has no folder context,
                // so omit "이 폴더에".
                emptyRow(text: "첫 문서를 만들어보세요.")
            } else {
                ForEach(viewModel.documents) { document in
                    // Tapping a document pushes `DetailView` for it
                    // (`Planning_6_FolderNavigationFlow` callout ⑤);
                    // "편집"/"삭제" open `RenameDocumentSheet`/a confirmation
                    // alert (`Planning_9_SwipeActionFlow` callouts ①–③).
                    // `DocumentRow` itself wraps the `NavigationLink`.
                    DocumentRow(
                        document: document,
                        onEdit: { entryBeingRenamed = .document(document) },
                        onDelete: { entryPendingDelete = .document(document) }
                    )
                }
            }
        } header: {
            sectionHeader("문서")
        }
    }
}

#Preview {
    HomeView()
        .environment(AppCommandCenter())
}
