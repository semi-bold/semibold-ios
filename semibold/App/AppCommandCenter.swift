import Foundation

/// Shared trigger point for app-level menu commands (macOS menu bar /
/// keyboard shortcuts, §13.2) that need to reach into `HomeScreen`'s
/// view-local "+" menu flows.
///
/// `HomeScreen` currently presents its "New Folder"/"New Document" sheets
/// from view-local `@State` (`Planning_2_FolderCreateFlow` /
/// `Planning_3_DocumentCreateFlow`). Rather than lifting that state into a
/// new app-wide view model, `SemiboldApp`'s `.commands` menu bumps a
/// counter here for the matching action; `HomeScreen` observes it via
/// `.environment` and opens the same sheet a tap on "+" would.
///
/// Counters (not booleans) so a second Cmd+N while the first sheet is still
/// open is still observable as a change once the user dismisses it.
@Observable
final class AppCommandCenter {
    /// Bumped when the user chooses "New Document" (Cmd+N) from the macOS
    /// app menu — `HomeScreen` opens its new-document sheet in response.
    private(set) var newDocumentRequestCount = 0

    /// Bumped when the user chooses "New Folder" (Cmd+Shift+N) from the
    /// macOS app menu — `HomeScreen` opens its new-folder sheet in response.
    private(set) var newFolderRequestCount = 0

    func requestNewDocument() {
        newDocumentRequestCount += 1
    }

    func requestNewFolder() {
        newFolderRequestCount += 1
    }
}
