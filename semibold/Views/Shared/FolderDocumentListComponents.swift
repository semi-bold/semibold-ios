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
        .foregroundStyle(AppTheme.Colors.Content.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(height: 32)
        .background(AppTheme.Colors.Neutral.n800)
        .listRowInsets(EdgeInsets())
}

/// Placeholder row shown while a section has no items.
func emptyRow(text: String) -> some View {
    Text(text)
        .appTextStyle(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.Content.secondary)
        .padding(.vertical, AppTheme.Spacing.sm)
        .listRowBackground(AppTheme.Colors.Neutral.n900)
}

/// Swipe-action button labels shared by `FolderRow`/`DocumentRow`, matching
/// `iOS_HomeViewSwipe`'s `SwipeAction_Edit`/`SwipeAction_Delete` layers
/// (`Planning_9_SwipeActionFlow` callouts ②③): "편집" in
/// `AppTheme.Colors.accent` (wireframe `#0a84ff`), "삭제" in
/// `AppTheme.Colors.Feedback.danger` with the destructive role (wireframe `#ff3b30`).
/// Both render as the standard 80pt-wide swipe button SwiftUI gives
/// `.swipeActions` buttons, matching the wireframe's `w=80` layers.
@ViewBuilder
private func editDeleteSwipeActions(onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
    // Left-to-right swipe-revealed order per `ios_homeviewswipe`: edit
    // (x=230) appears before delete (x=310), so edit is declared first —
    // `.swipeActions(edge: .trailing)` reveals trailing-most action
    // closest to the row's edge first when partially swiped.
    Button("편집", action: onEdit)
        .tint(AppTheme.Colors.accent)
    Button("삭제", role: .destructive, action: onDelete)
        .tint(AppTheme.Colors.Feedback.danger)
}

/// A single folder row: folder icon, name, and item count. Tapping it
/// pushes whatever `.navigationDestination(for: Folder.self)` resolves
/// to (registered once at the `NavigationStack` root in `HomeView`) —
/// wrapping `NavigationLink` here, instead of at each call site, is what
/// keeps the row-background fix below from having to be repeated/
/// remembered in `HomeView`/`FolderContentsView` separately.
///
/// Swiping left reveals "편집"/"삭제" actions (`iOS_HomeViewSwipe`,
/// `Planning_9_SwipeActionFlow` callouts ①–③). The actual rename/soft-delete
/// behavior is wired by the caller via `onEdit`/`onDelete`.
struct FolderRow: View {
    let folder: Folder
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        NavigationLink(value: folder) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "folder")
                    .foregroundStyle(AppTheme.Colors.Content.secondary)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(folder.name)
                        .appTextStyle(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.Content.primary)

                    // TODO: replace with the folder's actual child count
                    // once folder contents are loaded.
                    Text("0 items")
                        .appTextStyle(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.Content.secondary)
                }

                Spacer()
            }
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        // `NavigationLink` inside a `List` row otherwise paints its own
        // system row background (white) over whatever `listRowBackground`
        // is set, regardless of where that modifier is applied relative
        // to it — `.buttonStyle(.plain)` stops it from doing that, and
        // `.listRowBackground` then needs to sit on the `NavigationLink`
        // itself (not just inside its label content) to take effect.
        .buttonStyle(.plain)
        .listRowBackground(AppTheme.Colors.Neutral.n900)
        .swipeActions(edge: .trailing) {
            editDeleteSwipeActions(onEdit: onEdit, onDelete: onDelete)
        }
    }
}

/// A single document row: document icon, title, and last-updated date.
/// Tapping it pushes whatever `.navigationDestination(for: Document.self)`
/// resolves to (registered once at the `NavigationStack` root in
/// `HomeView`) — see `FolderRow`'s doc comment for why `NavigationLink`
/// is wrapped here rather than at each call site.
///
/// Swiping left reveals "편집"/"삭제" actions (`iOS_HomeViewSwipe`,
/// `Planning_9_SwipeActionFlow` callouts ①–③). The actual rename/soft-delete
/// behavior is wired by the caller via `onEdit`/`onDelete`.
struct DocumentRow: View {
    let document: Document
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        NavigationLink(value: document) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "doc.text")
                    .foregroundStyle(AppTheme.Colors.Content.secondary)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(document.title)
                        .appTextStyle(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.Content.primary)

                    Text(document.updatedAt.formatted(date: .numeric, time: .omitted))
                        .appTextStyle(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.Content.secondary)
                }

                Spacer()
            }
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        // See `FolderRow`'s matching comment — same `NavigationLink`
        // row-background fix applies here.
        .buttonStyle(.plain)
        .listRowBackground(AppTheme.Colors.Neutral.n900)
        .swipeActions(edge: .trailing) {
            editDeleteSwipeActions(onEdit: onEdit, onDelete: onDelete)
        }
    }
}
