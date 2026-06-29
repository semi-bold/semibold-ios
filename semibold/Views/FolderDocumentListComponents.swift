import SwiftUI

/// Shared row/section styling for screens that list folders and
/// documents — `HomeView` (`iOS_PrivateSpace`) and `FolderContentsView`
/// (`iOS_FolderContents`) both show the same "폴더"/"문서" section
/// layout, just scoped to a different parent folder, so the row/section
/// rendering lives here once instead of being duplicated per screen.

/// Section header styled like the wireframe's section-header bars: a
/// surface-colored bar with a small bold label ("폴더"/"문서" in
/// `ios_privatespace`/`ios_foldercontents`).
func sectionHeader(_ title: String) -> some View {
    Text(title)
        .appTextStyle(AppTheme.Typography.label)
        .foregroundStyle(AppTheme.Colors.text3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(height: 32)
        .background(AppTheme.Colors.surface)
        .listRowInsets(EdgeInsets())
}

/// Placeholder row shown while a section has no items.
func emptyRow(text: String) -> some View {
    Text(text)
        .appTextStyle(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.text2)
        .padding(.vertical, AppTheme.Spacing.sm)
        .listRowBackground(AppTheme.Colors.background)
}

/// A single folder row: folder icon, name, and item count.
struct FolderRow: View {
    let folder: Folder

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
        .listRowBackground(AppTheme.Colors.background)
    }
}

/// A single document row: document icon, title, and last-updated date.
struct DocumentRow: View {
    let document: Document

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
        .listRowBackground(AppTheme.Colors.background)
    }
}
