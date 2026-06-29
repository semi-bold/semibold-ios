import Foundation

/// Drives the "rename folder" name-entry sheet opened from the "편집"
/// swipe action on a folder row (`Planning_9_SwipeActionFlow`, NO-003
/// §3.2).
///
/// Mirrors `NewFolderViewModel`'s name-entry/validation shape, but loads
/// an existing folder's current name instead of starting blank, and
/// saves over that folder via `FolderRepository.update` instead of
/// creating a new row.
@Observable
final class RenameFolderViewModel {
    /// The name being edited, pre-filled with the folder's current name.
    var name: String

    /// Inline validation message shown under the name field, or `nil`
    /// when the current name has no error to report yet.
    private(set) var errorMessage: String?

    private let folder: Folder
    private let folderRepository: FolderRepository

    init(
        folder: Folder,
        folderRepository: FolderRepository = FolderRepository()
    ) {
        self.folder = folder
        self.name = folder.name
        self.folderRepository = folderRepository
    }

    /// Whether the Save action should be enabled. Mirrors the trimmed
    /// validation `renameFolder()` applies, so the button and the error
    /// message stay in sync.
    var canSave: Bool {
        !trimmedName.isEmpty
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates the current name and, if valid, saves it over the
    /// existing folder.
    ///
    /// - Returns: the updated folder on success, so the caller can
    ///   refresh its list. Returns `nil` when validation fails (folder
    ///   names can't be blank, same as creating one) or the save itself
    ///   fails; `errorMessage` is set so the sheet can show why and let
    ///   the user correct the name.
    @discardableResult
    func renameFolder() -> Folder? {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter a folder name."
            return nil
        }

        var updated = folder
        updated.name = trimmed

        do {
            let saved = try folderRepository.update(updated)
            errorMessage = nil
            return saved
        } catch {
            // §15.2 "저장 실패" — saving the renamed folder failed.
            errorMessage = AppErrorMessages.saveFailed
            return nil
        }
    }

    /// Clears any error once the user edits the name again, so the
    /// message doesn't linger after they've started fixing it.
    func nameDidChange() {
        errorMessage = nil
    }
}
