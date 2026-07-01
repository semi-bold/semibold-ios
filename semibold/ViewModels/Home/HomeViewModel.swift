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

    /// Set when a delete fails to persist, so `HomeView` can show the
    /// §15.2 "삭제 실패" alert. `nil` once dismissed.
    var errorMessage: String?

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

    /// Refreshes the list after a new folder is created
    /// (`Planning_2_FolderCreateFlow`'s final step, "폴더 목록 갱신" —
    /// the highlighted-selection step that used to follow it was removed
    /// from the spec, see NO-003 §1.4).
    func didCreateFolder() {
        load()
    }

    /// Refreshes the list after a new document is created
    /// (`Planning_3_DocumentCreateFlow`, PLANNING §5.3: "documents row
    /// 생성"). The user can then tap into the new document to open
    /// `DetailView`.
    func didCreateDocument() {
        load()
    }

    /// Refreshes the list after a folder is renamed via the "편집" swipe
    /// action (`Planning_9_SwipeActionFlow`).
    func didEditFolder() {
        load()
    }

    /// Refreshes the list after a document is renamed via the "편집"
    /// swipe action (`Planning_9_SwipeActionFlow`).
    func didEditDocument() {
        load()
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

    /// Soft-deletes `folder` after the confirmation alert and refreshes
    /// the list so it disappears (`Planning_9_SwipeActionFlow` callout
    /// ③). Nested folders/documents aren't touched directly — they simply
    /// stop being reachable once their parent is gone.
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
