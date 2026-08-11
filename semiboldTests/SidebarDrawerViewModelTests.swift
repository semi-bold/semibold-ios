import Foundation
import Testing

@testable import semibold

/// Tests for `SidebarDrawerViewModel`, which drives `SidebarDrawerView`'s
/// search bar (`tasks/NO-008.md` §3.2, `03-sidebar-drawer`).
///
/// Exercises the debounced search against a throwaway in-memory database,
/// the same way `DetailViewModelTests` exercises `DetailViewModel`'s own
/// debounced autosave — a near-zero `searchDebounceInterval` is injected
/// so tests don't wait out the real 300ms interval.
@MainActor
struct SidebarDrawerViewModelTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    private func makeViewModel(
        store: CoreDataTestStore,
        searchDebounceInterval: Duration = .milliseconds(10)
    ) -> SidebarDrawerViewModel {
        SidebarDrawerViewModel(
            folderRepository: FolderRepository(context: store.context),
            documentRepository: DocumentRepository(context: store.context),
            searchDebounceInterval: searchDebounceInterval
        )
    }

    @Test("With no keyword typed, there are no results and hasActiveKeyword is false")
    func startsWithNoResults() throws {
        let store = try makeStore()
        let viewModel = makeViewModel(store: store)

        #expect(viewModel.results.isEmpty)
        #expect(!viewModel.hasActiveKeyword)
    }

    @Test("Typing a keyword searches both folders and documents once the debounce settles, folders first")
    func typingKeywordFindsFoldersAndDocuments() async throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "스터디 자료"))
        let document = try documentRepository.create(Document(title: "스터디 노트"))

        let viewModel = makeViewModel(store: store)
        viewModel.keyword = "스터디"
        viewModel.keywordDidChange()

        #expect(viewModel.hasActiveKeyword)
        // Nothing yet — still waiting for the debounce to settle.
        #expect(viewModel.results.isEmpty)

        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.results.count == 2)
        if case .folder(let resultFolder) = viewModel.results[0] {
            #expect(resultFolder.id == folder.id)
        } else {
            Issue.record("Expected the first result to be the matching folder")
        }
        if case .document(let resultDocument, let parentFolderName) = viewModel.results[1] {
            #expect(resultDocument.id == document.id)
            #expect(parentFolderName == nil)
        } else {
            Issue.record("Expected the second result to be the matching document")
        }
    }

    @Test("A newer keystroke cancels the previous debounce timer so only the latest keyword is searched")
    func newerKeystrokeCancelsPreviousSearch() async throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        _ = try documentRepository.create(Document(title: "여행 계획"))
        _ = try documentRepository.create(Document(title: "스터디 노트"))

        let viewModel = makeViewModel(store: store)
        viewModel.keyword = "여행"
        viewModel.keywordDidChange()
        viewModel.keyword = "스터디"
        viewModel.keywordDidChange()

        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.results.count == 1)
        if case .document(let resultDocument, _) = viewModel.results.first {
            #expect(resultDocument.title == "스터디 노트")
        } else {
            Issue.record("Expected the settled search to be for the latest keyword only")
        }
    }

    @Test("Clearing the keyword back to blank clears the results immediately, without waiting for the debounce")
    func clearingKeywordClearsResultsImmediately() async throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        _ = try documentRepository.create(Document(title: "스터디 노트"))

        let viewModel = makeViewModel(store: store)
        viewModel.keyword = "스터디"
        viewModel.keywordDidChange()
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.results.count == 1)

        viewModel.keyword = ""
        viewModel.keywordDidChange()

        #expect(!viewModel.hasActiveKeyword)
        #expect(viewModel.results.isEmpty)
    }

    @Test("A keyword matching nothing settles to an empty result list")
    func keywordWithNoMatchesSettlesEmpty() async throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        _ = try documentRepository.create(Document(title: "여행 계획"))

        let viewModel = makeViewModel(store: store)
        viewModel.keyword = "존재하지않음"
        viewModel.keywordDidChange()

        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.hasActiveKeyword)
        #expect(viewModel.results.isEmpty)
    }

    @Test("reset() clears the keyword and results back to the drawer's default state")
    func resetClearsKeywordAndResults() async throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        _ = try documentRepository.create(Document(title: "스터디 노트"))

        let viewModel = makeViewModel(store: store)
        viewModel.keyword = "스터디"
        viewModel.keywordDidChange()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!viewModel.results.isEmpty)

        viewModel.reset()

        #expect(viewModel.keyword.isEmpty)
        #expect(viewModel.results.isEmpty)
        #expect(!viewModel.hasActiveKeyword)
    }
}
