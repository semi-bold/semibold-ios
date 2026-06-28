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
/// ④), and tapping a document row pushes `DetailView` (callout ⑤) — that
/// navigation wiring lands in a separate acceptance-criteria item, so
/// rows here are static for now.
struct FolderContentsView: View {
    @State private var viewModel: FolderContentsViewModel
    @Environment(\.dismiss) private var dismiss

    /// Whether the "+" menu (`iOS_AddMenu`) is showing. Wiring its
    /// "New Folder"/"New Document" actions to create items inside this
    /// folder is a separate acceptance-criteria item; the menu currently
    /// only offers "Cancel".
    @State private var isAddMenuPresented = false

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
            Button("Cancel", role: .cancel) {}
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

    /// "< Semi:bold" — returns to the previous screen in the navigation
    /// stack (`Planning_6_FolderNavigationFlow` callout ①). `NavigationStack`
    /// already supplies the system back gesture/button; this label just
    /// matches the wireframe's literal text since the system back button
    /// is hidden along with the rest of the nav bar (`.toolbar(.hidden)`).
    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Text("< Semi:bold")
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
                    FolderRow(folder: folder)
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
                    DocumentRow(document: document)
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
