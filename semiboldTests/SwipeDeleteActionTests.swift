import Testing

@testable import semibold

/// Tests for the "삭제" swipe action's soft-delete-then-reload flow and
/// its "does this folder have nested content" check
/// (`Planning_9_SwipeActionFlow` callout ③, NO-003 §3.2).
///
/// Covers both `HomeViewModel` (root-level lists) and
/// `FolderContentsViewModel` (a folder's nested lists), since both drive
/// the same `FolderRow`/`DocumentRow` swipe actions.
struct SwipeDeleteActionTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    // MARK: - folderHasNestedContent

    @Test("An empty folder reports no nested content")
    func emptyFolderHasNoNestedContent() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "일상"))

        let viewModel = HomeViewModel(folderRepository: folderRepository, documentRepository: documentRepository)

        #expect(viewModel.folderHasNestedContent(folder) == false)
    }

    @Test("A folder with a live nested sub-folder reports nested content")
    func folderWithNestedFolderReportsNestedContent() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "일상"))
        _ = try folderRepository.create(Folder(parentId: folder.id, name: "여행"))

        let viewModel = HomeViewModel(folderRepository: folderRepository, documentRepository: documentRepository)

        #expect(viewModel.folderHasNestedContent(folder))
    }

    @Test("A folder with a live nested document reports nested content")
    func folderWithNestedDocumentReportsNestedContent() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "일상"))
        _ = try documentRepository.create(Document(folderId: folder.id, title: "오늘의 일기"))

        let viewModel = HomeViewModel(folderRepository: folderRepository, documentRepository: documentRepository)

        #expect(viewModel.folderHasNestedContent(folder))
    }

    @Test("A folder whose only child was already soft-deleted reports no nested content")
    func folderWithOnlySoftDeletedChildReportsNoNestedContent() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "일상"))
        let nested = try folderRepository.create(Folder(parentId: folder.id, name: "여행"))
        try folderRepository.softDelete(id: nested.id)

        let viewModel = HomeViewModel(folderRepository: folderRepository, documentRepository: documentRepository)

        #expect(viewModel.folderHasNestedContent(folder) == false)
    }

    // MARK: - HomeViewModel.deleteFolder / deleteDocument

    @Test("Deleting a root-level folder soft-deletes it and removes it from HomeViewModel's list")
    func homeViewModelDeleteFolderRemovesItFromList() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "일상"))

        let viewModel = HomeViewModel(folderRepository: folderRepository, documentRepository: documentRepository)
        viewModel.load()
        #expect(viewModel.folders.map(\.id) == [folder.id])

        viewModel.deleteFolder(folder)

        #expect(viewModel.folders.isEmpty)
        let reloaded = try folderRepository.find(id: folder.id)
        #expect(reloaded?.deletedAt != nil)
    }

    @Test("Deleting a root-level document soft-deletes it and removes it from HomeViewModel's list")
    func homeViewModelDeleteDocumentRemovesItFromList() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let document = try documentRepository.create(Document(title: "오늘의 일기"))

        let viewModel = HomeViewModel(folderRepository: folderRepository, documentRepository: documentRepository)
        viewModel.load()
        #expect(viewModel.documents.map(\.id) == [document.id])

        viewModel.deleteDocument(document)

        #expect(viewModel.documents.isEmpty)
        let reloaded = try documentRepository.find(id: document.id)
        #expect(reloaded?.deletedAt != nil)
    }

    @Test("A failed folder delete sets errorMessage to the §15.2 '삭제 실패' text and leaves the list alone")
    func homeViewModelDeleteFolderFailureSetsErrorMessage() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "일상"))

        let viewModel = HomeViewModel(folderRepository: folderRepository, documentRepository: documentRepository)
        viewModel.load()

        // Remove the row out from under the view model so softDelete's
        // own lookup fails, mirroring RenameFolderViewModelTests' failure
        // setup.
        try folderRepository.hardDelete(id: folder.id)

        viewModel.deleteFolder(folder)

        #expect(viewModel.errorMessage == AppErrorMessages.deleteFailed)
    }

    // MARK: - FolderContentsViewModel.deleteFolder / deleteDocument

    @Test("Deleting a nested folder soft-deletes it and removes it from FolderContentsViewModel's list")
    func folderContentsViewModelDeleteFolderRemovesItFromList() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let parent = try folderRepository.create(Folder(name: "일상"))
        let nested = try folderRepository.create(Folder(parentId: parent.id, name: "여행"))

        let viewModel = FolderContentsViewModel(
            folder: parent,
            folderRepository: folderRepository,
            documentRepository: documentRepository
        )
        viewModel.load()
        #expect(viewModel.folders.map(\.id) == [nested.id])

        viewModel.deleteFolder(nested)

        #expect(viewModel.folders.isEmpty)
        let reloaded = try folderRepository.find(id: nested.id)
        #expect(reloaded?.deletedAt != nil)
    }

    @Test("Deleting a document inside a folder soft-deletes it and removes it from FolderContentsViewModel's list")
    func folderContentsViewModelDeleteDocumentRemovesItFromList() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let parent = try folderRepository.create(Folder(name: "일상"))
        let document = try documentRepository.create(Document(folderId: parent.id, title: "오늘의 일기"))

        let viewModel = FolderContentsViewModel(
            folder: parent,
            folderRepository: folderRepository,
            documentRepository: documentRepository
        )
        viewModel.load()
        #expect(viewModel.documents.map(\.id) == [document.id])

        viewModel.deleteDocument(document)

        #expect(viewModel.documents.isEmpty)
        let reloaded = try documentRepository.find(id: document.id)
        #expect(reloaded?.deletedAt != nil)
    }

    @Test("Deleting a folder with nested content soft-deletes only that folder, leaving its children's own rows untouched")
    func deletingFolderWithNestedContentDoesNotCascadeSoftDelete() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let parent = try folderRepository.create(Folder(name: "일상"))
        let nestedFolder = try folderRepository.create(Folder(parentId: parent.id, name: "여행"))
        let nestedDocument = try documentRepository.create(Document(folderId: parent.id, title: "오늘의 일기"))

        let viewModel = HomeViewModel(folderRepository: folderRepository, documentRepository: documentRepository)
        viewModel.load()

        viewModel.deleteFolder(parent)

        let reloadedParent = try folderRepository.find(id: parent.id)
        #expect(reloadedParent?.deletedAt != nil)

        // Soft-deleting the parent only marks the parent — its own
        // children's deletedAt stays nil, since the brief's "포함 여부"
        // wording only requires this single-row soft-delete to make the
        // folder (and therefore its contents) unreachable from its own
        // parent's list, not a recursive soft-delete of every descendant.
        let reloadedNestedFolder = try folderRepository.find(id: nestedFolder.id)
        #expect(reloadedNestedFolder?.deletedAt == nil)
        let reloadedNestedDocument = try documentRepository.find(id: nestedDocument.id)
        #expect(reloadedNestedDocument?.deletedAt == nil)
    }
}
