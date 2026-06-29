import Testing

@testable import semibold

/// Tests for `RenameDocumentViewModel`, which drives the "편집" swipe
/// action's rename sheet for a document row (`Planning_9_SwipeActionFlow`,
/// NO-003 §3.2).
struct RenameDocumentViewModelTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    @Test("The sheet starts pre-filled with the document's current title")
    func startsPrefilledWithCurrentTitle() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let document = try documentRepository.create(Document(title: "오늘의 일기"))

        let viewModel = RenameDocumentViewModel(document: document, documentRepository: documentRepository)

        #expect(viewModel.title == "오늘의 일기")
    }

    @Test("Saving a valid new title updates the document and is persisted")
    func renameDocumentPersistsNewTitle() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let document = try documentRepository.create(Document(title: "오늘의 일기"))

        let viewModel = RenameDocumentViewModel(document: document, documentRepository: documentRepository)
        viewModel.title = "내일의 일기"
        let renamed = viewModel.renameDocument()

        #expect(renamed?.id == document.id)
        #expect(renamed?.title == "내일의 일기")

        let reloaded = try documentRepository.find(id: document.id)
        #expect(reloaded?.title == "내일의 일기")
    }

    @Test("Saving a blank title falls back to 'Untitled', mirroring document creation")
    func renameDocumentFallsBackToUntitledWhenBlank() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let document = try documentRepository.create(Document(title: "오늘의 일기"))

        let viewModel = RenameDocumentViewModel(document: document, documentRepository: documentRepository)
        viewModel.title = "   "
        let renamed = viewModel.renameDocument()

        #expect(renamed?.title == "Untitled")

        let reloaded = try documentRepository.find(id: document.id)
        #expect(reloaded?.title == "Untitled")
    }

    @Test("Editing the title again clears a previous error message")
    func titleDidChangeClearsError() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let document = try documentRepository.create(Document(title: "오늘의 일기"))

        let viewModel = RenameDocumentViewModel(document: document, documentRepository: documentRepository)
        try documentRepository.hardDelete(id: document.id)
        viewModel.renameDocument()
        #expect(viewModel.errorMessage != nil)

        viewModel.titleDidChange()

        #expect(viewModel.errorMessage == nil)
    }

    @Test("A failed save sets errorMessage to the §15.2 '저장 실패' text")
    func renameDocumentFailureSetsSaveErrorMessage() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let document = try documentRepository.create(Document(title: "오늘의 일기"))

        let viewModel = RenameDocumentViewModel(document: document, documentRepository: documentRepository)
        viewModel.title = "내일의 일기"

        // Remove the document's row out from under the view model, so the
        // save (`update`) finds no matching row and throws
        // `RepositoryError.recordNotFound`.
        try documentRepository.hardDelete(id: document.id)

        let renamed = viewModel.renameDocument()

        #expect(renamed == nil)
        #expect(viewModel.errorMessage == AppErrorMessages.saveFailed)
    }
}
