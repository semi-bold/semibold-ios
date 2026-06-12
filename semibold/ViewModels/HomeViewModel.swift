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
}
