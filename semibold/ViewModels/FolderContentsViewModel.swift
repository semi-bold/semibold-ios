import Foundation

/// Drives `FolderContentsView` — the screen shown after tapping into a
/// folder, listing that folder's nested folders and documents.
///
/// Loads the folders and documents that live directly inside the given
/// folder from the local database, mirroring `HomeViewModel`'s pattern
/// for the root level.
@Observable
final class FolderContentsViewModel {
    let folder: Folder

    private(set) var folders: [Folder] = []
    private(set) var documents: [Document] = []

    private let folderRepository: FolderRepository
    private let documentRepository: DocumentRepository

    init(
        folder: Folder,
        folderRepository: FolderRepository = FolderRepository(),
        documentRepository: DocumentRepository = DocumentRepository()
    ) {
        self.folder = folder
        self.folderRepository = folderRepository
        self.documentRepository = documentRepository
    }

    /// Reloads the folders and documents nested directly inside `folder`.
    func load() {
        do {
            folders = try folderRepository.children(of: folder.id)
            documents = try documentRepository.documents(in: folder.id)
        } catch {
            // Same reasoning as `HomeViewModel.load()` — an empty list is
            // the safest fallback if the local database can't be read.
            folders = []
            documents = []
        }
    }

    /// Refreshes the list after a new nested folder is created inside
    /// this folder.
    func didCreateFolder() {
        load()
    }

    /// Refreshes the list after a new document is created inside this
    /// folder.
    func didCreateDocument() {
        load()
    }
}
