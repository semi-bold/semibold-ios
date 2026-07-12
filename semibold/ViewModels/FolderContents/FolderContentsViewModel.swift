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

    /// The back-button label `FolderContentsView`'s nav bar shows
    /// (`Planning_6_FolderNavigationFlow` callout ①). Starts out
    /// matching the root context's label and is replaced with the parent
    /// folder's name once `load()` looks it up, for folders nested
    /// inside another folder.
    private(set) var backButtonLabel = FolderBackButtonLabel.root

    /// Set when a delete fails to persist, so `FolderContentsView` can
    /// show the §15.2 "삭제 실패" alert. `nil` once dismissed.
    var errorMessage: String?

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

    /// Reloads the folders and documents nested directly inside `folder`,
    /// and resolves the back-button label for this depth.
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

        let parentName = folder.parentId.flatMap { parentId in
            try? folderRepository.find(id: parentId)?.name
        }
        backButtonLabel = FolderBackButtonLabel.resolve(parentId: folder.parentId, parentName: parentName)
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

    /// Refreshes the list after a nested folder is renamed via the
    /// "편집" swipe action (`Planning_9_SwipeActionFlow`).
    func didEditFolder() {
        load()
    }

    /// Refreshes the list after a document is renamed via the "편집"
    /// swipe action (`Planning_9_SwipeActionFlow`).
    func didEditDocument() {
        load()
    }

    /// Total number of direct children (sub-folders + documents) inside
    /// `folder`, for display in `FolderRow`'s subText.
    func childCount(for folder: Folder) -> Int {
        let subFolders = (try? folderRepository.childCount(of: folder.id)) ?? 0
        let docs = (try? documentRepository.count(in: folder.id)) ?? 0
        return subFolders + docs
    }

    /// Whether `folder` has any live (non-soft-deleted) nested folders or
    /// documents — used by the "삭제" swipe action's confirmation alert
    /// to warn that deleting it will also take its contents out of view
    /// (`Planning_9_SwipeActionFlow` callout ③, "하위 폴더·문서가 있는
    /// 폴더 삭제 시 포함 여부를 묻는 다이얼로그").
    func folderHasNestedContent(_ folder: Folder) -> Bool {
        let hasNestedFolders = (try? folderRepository.hasChildren(of: folder.id)) ?? false
        let hasNestedDocuments = (try? documentRepository.hasDocuments(in: folder.id)) ?? false
        return hasNestedFolders || hasNestedDocuments
    }

    /// Soft-deletes a nested `folder` after the confirmation alert and
    /// refreshes the list so it disappears (`Planning_9_SwipeActionFlow`
    /// callout ③). Nested folders/documents aren't touched directly —
    /// they simply stop being reachable once their parent is gone.
    func deleteFolder(_ folder: Folder) {
        do {
            try folderRepository.softDelete(id: folder.id)
            load()
        } catch {
            // §15.2 "삭제 실패" — the folder stays visible if the delete
            // couldn't be persisted.
            errorMessage = AppErrorMessages.deleteFailed
        }
    }

    /// Soft-deletes `document` after the confirmation alert and refreshes
    /// the list so it disappears (`Planning_9_SwipeActionFlow` callout
    /// ③).
    func deleteDocument(_ document: Document) {
        do {
            try documentRepository.softDelete(id: document.id)
            load()
        } catch {
            // §15.2 "삭제 실패" — the document stays visible if the
            // delete couldn't be persisted.
            errorMessage = AppErrorMessages.deleteFailed
        }
    }
}
