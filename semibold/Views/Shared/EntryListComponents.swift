import SwiftUI

/// Shared row/section styling for screens that list folders and
/// documents — `HomeView` (`iOS_PrivateSpace`) and `FolderContentsView`
/// (`iOS_FolderContents`) both show the same "폴더"/"문서" section
/// layout, just scoped to a different parent folder, so the row/section
/// rendering lives here once instead of being duplicated per screen.

// MARK: - Section helpers

func sectionHeader(_ title: String) -> some View {
    Text(title)
        .appTextStyle(AppTheme.Typography.label)
        .foregroundStyle(AppTheme.Colors.Content.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(height: 32)
        .background(AppTheme.Colors.Neutral.n800)
        .listRowInsets(EdgeInsets())
}

func emptyRow(text: String) -> some View {
    Text(text)
        .appTextStyle(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.Content.secondary)
        .padding(.vertical, AppTheme.Spacing.sm)
        .listRowBackground(AppTheme.Colors.Neutral.n900)
}

// MARK: - Shared sections

func folderSection(
    folders: [Folder],
    emptyText: String,
    childCountFor: @escaping (Folder) -> Int,
    onEdit: @escaping (Folder) -> Void,
    onDelete: @escaping (Folder) -> Void
) -> some View {
    Section {
        if folders.isEmpty {
            emptyRow(text: emptyText)
        } else {
            ForEach(folders) { folder in
                FolderRow(
                    folder: folder,
                    childCount: childCountFor(folder),
                    onEdit: { onEdit(folder) },
                    onDelete: { onDelete(folder) }
                )
            }
        }
    } header: {
        sectionHeader("폴더")
    }
}

func documentSection(
    documents: [Document],
    emptyText: String,
    onEdit: @escaping (Document) -> Void,
    onDelete: @escaping (Document) -> Void
) -> some View {
    Section {
        if documents.isEmpty {
            emptyRow(text: emptyText)
        } else {
            ForEach(documents) { document in
                DocumentRow(
                    document: document,
                    onEdit: { onEdit(document) },
                    onDelete: { onDelete(document) }
                )
            }
        }
    } header: {
        sectionHeader("문서")
    }
}

// MARK: - Base row

/// Base list row for any Entry (Folder or Document). Owns the shared
/// layout — icon, primary text, subText — and the "편집"/"삭제" swipe
/// actions. `Value` is the `NavigationLink` destination type so both
/// `Folder` and `Document` can reuse this view without casting.
struct EntryRow<Value: Hashable>: View {
    let value: Value
    let icon: String
    let name: String
    let subText: String
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.Colors.Content.secondary)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(name)
                        .appTextStyle(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.Content.primary)

                    Text(subText)
                        .appTextStyle(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.Content.secondary)
                }

                Spacer()
            }
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .listRowBackground(AppTheme.Colors.Neutral.n900)
        .swipeActions(edge: .trailing) {
            Button("편집", action: onEdit)
                .tint(AppTheme.Colors.accent)
            Button("삭제", role: .destructive, action: onDelete)
                .tint(AppTheme.Colors.Feedback.danger)
        }
    }
}

// MARK: - Typed wrappers

/// Folder row — passes folder-specific props into `EntryRow`.
struct FolderRow: View {
    let folder: Folder
    var childCount: Int = 0
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        EntryRow(
            value: folder,
            icon: "folder",
            name: folder.name,
            subText: childCount == 1 ? "1 item" : "\(childCount) items",
            onEdit: onEdit,
            onDelete: onDelete
        )
    }
}

/// Document row — passes document-specific props into `EntryRow`.
struct DocumentRow: View {
    let document: Document
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        EntryRow(
            value: document,
            icon: "doc.text",
            name: document.title,
            subText: document.updatedAt.formatted(date: .numeric, time: .omitted),
            onEdit: onEdit,
            onDelete: onDelete
        )
    }
}
