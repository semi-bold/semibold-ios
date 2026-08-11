import Foundation

/// Drives the "new folder" name-entry sheet opened from `HomeScreen`'s "+"
/// menu (`Planning_2_FolderCreateFlow`, PLANNING §5.2).
///
/// Walks through the flow's state diagram: the user types a name, the
/// name is validated, an invalid name shows an inline error and keeps the
/// sheet open, and a valid name is saved as a new root-level folder.
@Observable
final class NewFolderViewModel {
    /// The name the user is typing for the new folder.
    var name: String = ""

    /// Inline validation message shown under the name field, or `nil`
    /// when the current name (or an untouched field) has no error to
    /// report yet.
    private(set) var errorMessage: String?

    private let folderRepository: FolderRepository

    /// The folder the user is creating this inside of. `nil` means the
    /// root of the Private space, matching `HomeViewModel`'s root list.
    private let parentId: String?

    init(
        parentId: String? = nil,
        folderRepository: FolderRepository = FolderRepository()
    ) {
        self.parentId = parentId
        self.folderRepository = folderRepository
    }

    /// Whether the Create action should be enabled. Mirrors the trimmed
    /// validation `createFolder()` applies, so the button and the error
    /// message stay in sync.
    var canCreate: Bool {
        !trimmedName.isEmpty
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates the current name and, if valid, saves a new folder.
    ///
    /// - Returns: the created folder on success, so the caller can
    ///   refresh its list and select the new folder
    ///   (PLANNING §5.2: "폴더 목록 갱신" → "생성된 폴더 선택 상태로 전환").
    ///   Returns `nil` when validation fails; `errorMessage` is set so the
    ///   sheet can show why and let the user correct the name.
    @discardableResult
    func createFolder() -> Folder? {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter a folder name."
            return nil
        }

        do {
            let folder = Folder(parentId: parentId, name: trimmed)
            let created = try folderRepository.create(folder)
            errorMessage = nil
            return created
        } catch {
            // §15.2 "저장 실패" — saving a new folder failed.
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
