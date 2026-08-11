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
    /// No longer called directly from this screen (the account row that
    /// used to trigger it moved into the navigation drawer,
    /// `03-sidebar-drawer`/`04-account-tooltip-and-alerts`) — `SemiboldApp`
    /// still passes it in so it can build `AccountActionCenter.resetToOnboarding`
    /// from the same closure, keeping one source of truth for this path.
    var onResetToOnboarding: (() -> Void)?

    @State private var viewModel = HomeViewModel()

    /// Shared trigger point for the macOS "New Document"/"New Folder" menu
    /// commands (Cmd+N / Cmd+Shift+N, §13.2) — see `AppCommandCenter`.
    @Environment(AppCommandCenter.self) private var commandCenter

    /// Whether the "+" menu (`iOS_AddMenu`) is showing, offering "New
    /// Folder" / "New Document" / "Cancel" (callouts ④/⑤ of
    /// `Planning_2_FolderCreateFlow` / `Planning_3_DocumentCreateFlow`).
    @State private var isAddMenuPresented = false

    /// Whether the navigation drawer (`icon_menu` in
    /// `Planning_Nav_1_TopBarFlow`) is showing — presented via
    /// `SidebarDrawerView`, `03-sidebar-drawer`'s search-first drawer
    /// (`Planning_Nav_2_DrawerFlow`).
    @State private var isDrawerPresented = false

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
                    folderSection(
                        folders: viewModel.folders,
                        emptyText: "첫 폴더를 만들어보세요.",
                        childCountFor: { viewModel.childCount(for: $0) },
                        onEdit: { entryBeingRenamed = .folder($0) },
                        onDelete: { entryPendingDelete = .folder($0) }
                    )
                    documentSection(
                        documents: viewModel.documents,
                        emptyText: "첫 문서를 만들어보세요.",
                        onEdit: { entryBeingRenamed = .document($0) },
                        onDelete: { entryPendingDelete = .document($0) }
                    )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(AppTheme.Colors.Neutral.n900)
            .overlay(alignment: .bottomTrailing) {
                floatingAddButton
                    .padding(.trailing, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.md)
            }
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
            .overlay {
                // Registered after both `navigationDestination`s above so
                // the drawer's own search-result rows push through those
                // same destinations, the same way this screen's own
                // `FolderRow`/`DocumentRow` rows do
                // (`SidebarDrawerView`'s doc comment).
                SidebarDrawerView(isPresented: $isDrawerPresented)
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

    /// Top bar: app name and the drawer's menu (hamburger) button. The
    /// account button and the "+" that used to sit here both moved out —
    /// the account row now lives in `SidebarDrawerView`
    /// (`03-sidebar-drawer`/`04-account-tooltip-and-alerts`), and "+" moved
    /// to `floatingAddButton` (`Planning_Nav_1_TopBarFlow`, FLOW-NAV-001).
    /// Shared chrome (height/divider/background) lives in `NavBar`
    /// (`Views/NavBar/NavBar.swift`) — this screen only supplies its
    /// leading content.
    private var navBar: some View {
        NavBar(
            leading: {
                Image("AppWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
            },
            onMenuTapped: {
                isDrawerPresented = true
            }
        )
    }

    /// Entry point for the "new folder / new document" menu
    /// (`Planning_2_FolderCreateFlow` / `Planning_3_DocumentCreateFlow`,
    /// callout ① — "현재 보고 있는 위치를 기준으로 무언가를 새로 만들기
    /// 시작하는 단일 진입점"). Floating at the screen's bottom-trailing
    /// corner (`FAB_AddMenu`) as of `Planning_Nav_1_TopBarFlow`, rather
    /// than inline in the NavBar.
    private var floatingAddButton: some View {
        AddButton(placement: .floating) {
            isAddMenuPresented = true
        }
    }

}

#Preview {
    HomeView()
        .environment(AppCommandCenter())
        .environment(AccountActionCenter())
}
