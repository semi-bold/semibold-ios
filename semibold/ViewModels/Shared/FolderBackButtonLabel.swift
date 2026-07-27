import Foundation

/// Decides what `FolderContentsView`'s and `DetailView`'s nav bar back
/// buttons show — both screens follow the same icon-only rule.
///
/// Pulled out of `FolderContentsViewModel` so this branching logic has a
/// plain value type that's testable without standing up a Core Data
/// context, the same reasoning behind `RootLaunchState`.
enum FolderBackButtonLabel: Equatable {
    /// The folder/document being shown is at the root of the user's
    /// document tree (`parentId`/`folderId == nil`) — going back returns
    /// to `HomeView`.
    case root
    /// The folder/document being shown is filed inside a folder — going
    /// back returns to that folder's own `FolderContentsView`. `name`
    /// isn't shown as visible text (see `iconName`) — kept only for
    /// `accessibilityLabel`, since VoiceOver still needs to say where the
    /// button goes even though the icon alone doesn't.
    case parentFolder(name: String)

    /// The SF Symbol `FolderContentsView`'s back button shows — icon-only,
    /// no folder-name text, per `Planning_6_FolderNavigationFlow` callout
    /// ①'s revised spec: a house for the root case (returning to Private
    /// Space) and a plain chevron for a nested folder (returning to its
    /// parent), rather than repeating "Semi:bold" or a folder name that
    /// could run arbitrarily long and break the NavBar's layout.
    var iconName: String {
        switch self {
        case .root:
            return "house.fill"
        case .parentFolder:
            return "chevron.left"
        }
    }

    /// VoiceOver label naming the destination this button returns to,
    /// since `iconName` alone doesn't say it visually.
    var accessibilityLabel: String {
        switch self {
        case .root:
            return "뒤로가기, 홈"
        case .parentFolder(let name):
            return "뒤로가기, \(name)"
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
