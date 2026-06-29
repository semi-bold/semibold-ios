import Foundation

/// Decides what `FolderContentsView`'s nav bar back button should read.
///
/// Pulled out of `FolderContentsViewModel` so this branching logic has a
/// plain value type that's testable without standing up a Core Data
/// context, the same reasoning behind `RootLaunchState`.
enum FolderBackButtonLabel: Equatable {
    /// The folder being shown is at the root of the user's document tree
    /// (`parentId == nil`) — going back returns to `HomeView`, so the
    /// label stays the literal "< Semi:bold"
    /// (`Planning_6_FolderNavigationFlow` callout ①).
    case root
    /// The folder being shown is nested inside another folder — going
    /// back returns to that parent folder's own `FolderContentsView`, so
    /// the label names it directly (e.g. "< 일상") instead of repeating
    /// the app name.
    case parentFolder(name: String)

    /// The literal text the back button displays.
    var text: String {
        switch self {
        case .root:
            return "< Semi:bold"
        case .parentFolder(let name):
            return "< \(name)"
        }
    }

    /// Computes which label `FolderContentsView` should show for the
    /// folder currently on screen.
    ///
    /// - Parameters:
    ///   - parentId: The current folder's `parentId`. `nil` means the
    ///     current folder is at the root, so there's no parent folder
    ///     name to show.
    ///   - parentName: The parent folder's name, already looked up by
    ///     the caller (e.g. via `FolderRepository.find(id:)`) when
    ///     `parentId` isn't `nil`. Ignored when `parentId` is `nil`.
    ///     `nil` here (parent lookup failed, e.g. a since-deleted
    ///     folder) falls back to `.root` rather than showing a blank
    ///     name.
    static func resolve(parentId: String?, parentName: String?) -> FolderBackButtonLabel {
        guard parentId != nil, let parentName else {
            return .root
        }
        return .parentFolder(name: parentName)
    }
}
