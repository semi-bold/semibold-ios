import Testing

@testable import semibold

/// Round-trip tests for the folder/document repositories backing
/// `HomeView`'s lists.
///
/// These exercise the same path `HomeViewModel` relies on end-to-end:
/// create a row through the repository, then read it back the way
/// `HomeViewModel.load()` does (`children(of:)` / `documents(in:)`), all
/// against a throwaway in-memory database so the on-disk
/// `semibold.sqlite` is never touched.
struct FolderDocumentPersistenceTests {
    /// A fresh, fully-migrated in-memory database for one test.
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    @Test("A created root-level folder is persisted and shows up in HomeView's folder list")
    func createFolderPersistsAndIsListed() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)

        let folder = Folder(name: "Recipes")
        let created = try folderRepository.create(folder)

        #expect(created.id == folder.id)
        #expect(created.name == "Recipes")

        // What HomeViewModel.load() calls for the root-level folder section.
        let rootFolders = try folderRepository.children(of: nil)
        #expect(rootFolders.map(\.id) == [folder.id])
        #expect(rootFolders.first?.name == "Recipes")
    }

    @Test("A created root-level document is persisted and shows up in HomeView's document list")
    func createDocumentPersistsAndIsListed() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = Document(title: "Project Plan")
        let created = try documentRepository.create(document)

        #expect(created.id == document.id)
        #expect(created.title == "Project Plan")

        // What HomeViewModel.load() calls for the root-level document section.
        let rootDocuments = try documentRepository.documents(in: nil)
        #expect(rootDocuments.map(\.id) == [document.id])
        #expect(rootDocuments.first?.title == "Project Plan")
    }

    @Test("Root-level folders are listed newest-created first")
    func rootFoldersAreListedNewestFirst() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)

        let oldest = try folderRepository.create(Folder(name: "Oldest", createdAt: Date(timeIntervalSince1970: 0)))
        let middle = try folderRepository.create(Folder(name: "Middle", createdAt: Date(timeIntervalSince1970: 100)))
        let newest = try folderRepository.create(Folder(name: "Newest", createdAt: Date(timeIntervalSince1970: 200)))

        let rootFolders = try folderRepository.children(of: nil)
        #expect(rootFolders.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test("Root-level documents are listed newest-created first")
    func rootDocumentsAreListedNewestFirst() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let oldest = try documentRepository.create(Document(title: "Oldest", createdAt: Date(timeIntervalSince1970: 0)))
        let middle = try documentRepository.create(Document(title: "Middle", createdAt: Date(timeIntervalSince1970: 100)))
        let newest = try documentRepository.create(Document(title: "Newest", createdAt: Date(timeIntervalSince1970: 200)))

        let rootDocuments = try documentRepository.documents(in: nil)
        #expect(rootDocuments.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test("A document created inside a folder is not listed at the root")
    func documentInFolderIsScopedToThatFolder() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)

        let folder = try folderRepository.create(Folder(name: "Work"))
        _ = try documentRepository.create(Document(folderId: folder.id, title: "Notes"))

        let rootDocuments = try documentRepository.documents(in: nil)
        #expect(rootDocuments.isEmpty)

        let folderDocuments = try documentRepository.documents(in: folder.id)
        #expect(folderDocuments.map(\.title) == ["Notes"])
    }

    @Test("FolderContentsViewModel resolves the literal Semi:bold back label for a root-level folder")
    func folderContentsViewModelResolvesRootBackLabel() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)

        let folder = try folderRepository.create(Folder(name: "일상"))

        let viewModel = FolderContentsViewModel(
            folder: folder,
            folderRepository: folderRepository,
            documentRepository: documentRepository
        )
        viewModel.load()

        #expect(viewModel.backButtonLabel == .root)
    }

    @Test("FolderContentsViewModel resolves the parent folder's name as the back label for a nested folder")
    func folderContentsViewModelResolvesParentNameBackLabel() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)

        let parent = try folderRepository.create(Folder(name: "일상"))
        let nested = try folderRepository.create(Folder(parentId: parent.id, name: "여행"))

        let viewModel = FolderContentsViewModel(
            folder: nested,
            folderRepository: folderRepository,
            documentRepository: documentRepository
        )
        viewModel.load()

        #expect(viewModel.backButtonLabel == .parentFolder(name: "일상"))
        #expect(viewModel.backButtonLabel.iconName == "chevron.left")
    }
}
