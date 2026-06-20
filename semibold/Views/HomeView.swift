import SwiftUI

/// The Private Layer's home screen: the top-level folder and document
/// list a user sees when they open the app.
///
/// Matches the `Screen_Home` wireframe (`iOS_PrivateSpace` artboard in
/// `sketch-autokit/screens/wireframe.py`) — a navigation bar showing the
/// current space ("Private") and an add button, followed by a "Folders"
/// section and a "Documents" section listing everything at the root of
/// the user's document tree.
struct HomeView: View {
    @State private var viewModel = HomeViewModel()

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

    /// Whether `SettingsView` (currently scoped to the "동기화" section,
    /// NO-002) is showing.
    @State private var isSettingsSheetPresented = false

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
            NewFolderSheet { createdFolder in
                viewModel.didCreateFolder(createdFolder)
            }
        }
        .sheet(isPresented: $isNewDocumentSheetPresented) {
            NewDocumentSheet { createdDocument in
                viewModel.didCreateDocument(createdDocument)
            }
        }
        .sheet(isPresented: $isSettingsSheetPresented) {
            SettingsView()
        }
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

                settingsButton

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

    /// Entry point for `SettingsView` (currently scoped to the "동기화"
    /// section, NO-002) — not specified in `Screen_Home`/`iOS_PrivateSpace`,
    /// so it's placed beside `addButton` using the same icon-button style
    /// (see `.claude/features/04-settings-screen.md` Decisions &
    /// Deviations).
    private var settingsButton: some View {
        Button {
            isSettingsSheetPresented = true
        } label: {
            Image(systemName: "gearshape")
                .appTextStyle(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.primary)
                .frame(width: 40, height: 40)
                .background(
                    AppTheme.Colors.primary.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                )
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
                    FolderRow(folder: folder, isSelected: folder.id == viewModel.selectedFolderId)
                }
            }
        } header: {
            sectionHeader("Folders")
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
                    DocumentRow(document: document, isSelected: document.id == viewModel.selectedDocumentId)
                }
            }
        } header: {
            sectionHeader("Documents")
        }
    }

    /// Section header styled like the wireframe's `SectionHeader_*`
    /// groups: a surface-colored bar with an uppercase label.
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .appTextStyle(AppTheme.Typography.label)
            .foregroundStyle(AppTheme.Colors.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 32)
            .background(AppTheme.Colors.surface)
            .listRowInsets(EdgeInsets())
    }

    /// Placeholder row shown while a section has no items.
    private func emptyRow(text: String) -> some View {
        Text(text)
            .appTextStyle(AppTheme.Typography.body)
            .foregroundStyle(AppTheme.Colors.text2)
            .padding(.vertical, AppTheme.Spacing.sm)
            .listRowBackground(AppTheme.Colors.background)
    }
}

/// A single folder row: folder icon, name, and item count.
private struct FolderRow: View {
    let folder: Folder

    /// Whether this is the folder just created from the "+" menu
    /// (PLANNING §5.2: "생성된 폴더 선택 상태로 전환"), highlighted so the
    /// user can see where it landed in the list.
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "folder")
                .foregroundStyle(AppTheme.Colors.text2)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(folder.name)
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.text1)

                // TODO: replace with the folder's actual child count once
                // folder contents are loaded.
                Text("0 items")
                    .appTextStyle(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.text2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .appTextStyle(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.text3)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .listRowBackground(isSelected ? AppTheme.Colors.surface2 : AppTheme.Colors.background)
    }
}

/// A single document row: document icon, title, and last-updated date.
private struct DocumentRow: View {
    let document: Document

    /// Whether this is the document just created from the "+" menu
    /// (`Planning_3_DocumentCreateFlow`, PLANNING §5.3), highlighted so the
    /// user can see where it landed in the list.
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "doc.text")
                .foregroundStyle(AppTheme.Colors.text2)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(document.title)
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.text1)

                Text(document.updatedAt.formatted(date: .numeric, time: .omitted))
                    .appTextStyle(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.text2)
            }

            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .listRowBackground(isSelected ? AppTheme.Colors.surface2 : AppTheme.Colors.background)
    }
}

#Preview {
    HomeView()
        .environment(AppCommandCenter())
}
