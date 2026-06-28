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
}
