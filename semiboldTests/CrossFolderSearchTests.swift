import Foundation
import Testing

@testable import semibold

/// Tests for the whole-tree keyword search added to `DocumentRepository`
/// and `FolderRepository` for the sidebar drawer's search bar
/// (`tasks/NO-008.md` §2.1) — matches must span every nested folder, not
/// just one folder's direct children, and stay excluded/empty exactly
/// like every other list query when rows are soft-deleted or the keyword
/// is blank.
struct CrossFolderSearchTests {
    /// A fresh, fully-migrated in-memory database for one test.
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    // MARK: - DocumentRepository.search(keyword:)

    @Test("Document search finds a title match nested inside a grandchild folder, with the immediate parent's name attached")
    func documentSearchFindsMatchInNestedGrandchildFolder() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)

        let grandparent = try folderRepository.create(Folder(name: "학교"))
        let parent = try folderRepository.create(Folder(parentId: grandparent.id, name: "동아리"))
        let child = try folderRepository.create(Folder(parentId: parent.id, name: "스터디"))
        _ = try documentRepository.create(Document(folderId: child.id, title: "알고리즘 스터디 노트"))

        let results = try documentRepository.search(keyword: "스터디")

        #expect(results.count == 1)
        #expect(results.first?.document.title == "알고리즘 스터디 노트")
        #expect(results.first?.parentFolderName == "스터디")
    }

    @Test("Document search finds a root-level document and reports no parent folder")
    func documentSearchFindsRootDocumentWithNilParent() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        _ = try documentRepository.create(Document(title: "스터디 계획"))

        let results = try documentRepository.search(keyword: "스터디")

        #expect(results.count == 1)
        #expect(results.first?.document.title == "스터디 계획")
        #expect(results.first?.parentFolderName == nil)
    }

    @Test("Document search is case-insensitive")
    func documentSearchIsCaseInsensitive() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        _ = try documentRepository.create(Document(title: "Project Roadmap"))

        let results = try documentRepository.search(keyword: "roadmap")
        #expect(results.map(\.document.title) == ["Project Roadmap"])
    }

    @Test("Document search returns nothing when no title matches")
    func documentSearchReturnsEmptyWhenNoMatch() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        _ = try documentRepository.create(Document(title: "Project Roadmap"))

        let results = try documentRepository.search(keyword: "여행")
        #expect(results.isEmpty)
    }

    @Test("Document search excludes soft-deleted documents")
    func documentSearchExcludesSoftDeletedDocuments() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "스터디 노트"))
        try documentRepository.softDelete(id: document.id)

        let results = try documentRepository.search(keyword: "스터디")
        #expect(results.isEmpty)
    }

    @Test("Document search returns an empty result for a blank keyword instead of every document")
    func documentSearchReturnsEmptyForBlankKeyword() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)

        _ = try documentRepository.create(Document(title: "Project Roadmap"))

        #expect(try documentRepository.search(keyword: "").isEmpty)
        #expect(try documentRepository.search(keyword: "   ").isEmpty)
    }

    // MARK: - FolderRepository.search(keyword:)

    @Test("Folder search finds a name match nested inside a grandchild folder")
    func folderSearchFindsMatchInNestedGrandchildFolder() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)

        let grandparent = try folderRepository.create(Folder(name: "학교"))
        let parent = try folderRepository.create(Folder(parentId: grandparent.id, name: "동아리"))
        let target = try folderRepository.create(Folder(parentId: parent.id, name: "스터디"))

        let results = try folderRepository.search(keyword: "스터디")
        #expect(results.map(\.id) == [target.id])
    }

    @Test("Folder search returns nothing when no name matches")
    func folderSearchReturnsEmptyWhenNoMatch() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)

        _ = try folderRepository.create(Folder(name: "학교"))

        let results = try folderRepository.search(keyword: "여행")
        #expect(results.isEmpty)
    }

    @Test("Folder search excludes soft-deleted folders")
    func folderSearchExcludesSoftDeletedFolders() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)

        let folder = try folderRepository.create(Folder(name: "스터디"))
        try folderRepository.softDelete(id: folder.id)

        let results = try folderRepository.search(keyword: "스터디")
        #expect(results.isEmpty)
    }

    @Test("Folder search returns an empty result for a blank keyword instead of the whole tree")
    func folderSearchReturnsEmptyForBlankKeyword() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)

        _ = try folderRepository.create(Folder(name: "학교"))

        #expect(try folderRepository.search(keyword: "").isEmpty)
        #expect(try folderRepository.search(keyword: "   ").isEmpty)
    }
}
