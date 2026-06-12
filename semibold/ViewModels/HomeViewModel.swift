import Foundation

/// Drives `HomeView` — the Private Layer's top-level folder/document
/// list.
///
/// Loads the root-level folders and documents (the ones with no parent
/// folder) from the local database so the home screen always reflects
/// what's actually been saved.
@Observable
final class HomeViewModel {
    private(set) var folders: [Folder] = []
    private(set) var documents: [Document] = []

    /// The folder most recently created from the "+" menu, highlighted in
    /// the list to confirm where it landed
    /// (PLANNING §5.2: "생성된 폴더 선택 상태로 전환").
    var selectedFolderId: String?

    private let folderRepository: FolderRepository
    private let documentRepository: DocumentRepository

    init(
        folderRepository: FolderRepository = FolderRepository(),
        documentRepository: DocumentRepository = DocumentRepository()
    ) {
        self.folderRepository = folderRepository
        self.documentRepository = documentRepository
    }

    /// Reloads the root-level folders and documents shown on the home
    /// screen.
    func load() {
        do {
            folders = try folderRepository.children(of: nil)
            documents = try documentRepository.documents(in: nil)
        } catch {
            // The home list simply stays empty if it can't be read; the
            // local database is expected to always be available, so this
            // would indicate a deeper setup problem rather than something
            // the user can act on here.
            folders = []
            documents = []
        }
    }

    /// Refreshes the list after a new folder is created and marks it as
    /// selected, completing `Planning_2_FolderCreateFlow`'s final two
    /// steps ("폴더 목록 갱신" → "생성된 폴더 선택 상태로 전환").
    func didCreateFolder(_ folder: Folder) {
        load()
        selectedFolderId = folder.id
    }
}
