import Testing

@testable import semibold

/// Tests for `RenameFolderViewModel`, which drives the "편집" swipe
/// action's rename sheet for a folder row (`Planning_9_SwipeActionFlow`,
/// NO-003 §3.2).
struct RenameFolderViewModelTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    @Test("The sheet starts pre-filled with the folder's current name")
    func startsPrefilledWithCurrentName() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "일상"))

        let viewModel = RenameFolderViewModel(folder: folder, folderRepository: folderRepository)

        #expect(viewModel.name == "일상")
    }

    @Test("Saving a valid new name updates the folder and is persisted")
    func renameFolderPersistsNewName() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "일상"))

        let viewModel = RenameFolderViewModel(folder: folder, folderRepository: folderRepository)
        viewModel.name = "여행"
        let renamed = viewModel.renameFolder()

        #expect(renamed?.id == folder.id)
        #expect(renamed?.name == "여행")

        let reloaded = try folderRepository.find(id: folder.id)
        #expect(reloaded?.name == "여행")
    }

    @Test("Saving a blank name fails validation and leaves the folder unchanged")
    func renameFolderRejectsBlankName() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "일상"))

        let viewModel = RenameFolderViewModel(folder: folder, folderRepository: folderRepository)
        viewModel.name = "   "
        let renamed = viewModel.renameFolder()

        #expect(renamed == nil)
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.canSave)

        let reloaded = try folderRepository.find(id: folder.id)
        #expect(reloaded?.name == "일상")
    }

    @Test("Editing the name again clears a previous error message")
    func nameDidChangeClearsError() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "일상"))

        let viewModel = RenameFolderViewModel(folder: folder, folderRepository: folderRepository)
        viewModel.name = ""
        viewModel.renameFolder()
        #expect(viewModel.errorMessage != nil)

        viewModel.name = "여행"
        viewModel.nameDidChange()

        #expect(viewModel.errorMessage == nil)
    }

    @Test("A failed save sets errorMessage to the §15.2 '저장 실패' text")
    func renameFolderFailureSetsSaveErrorMessage() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let folder = try folderRepository.create(Folder(name: "일상"))

        let viewModel = RenameFolderViewModel(folder: folder, folderRepository: folderRepository)
        viewModel.name = "여행"

        // Remove the folder's row out from under the view model, so the
        // save (`update`) finds no matching row and throws
        // `RepositoryError.recordNotFound`.
        try folderRepository.hardDelete(id: folder.id)

        let renamed = viewModel.renameFolder()

        #expect(renamed == nil)
        #expect(viewModel.errorMessage == AppErrorMessages.saveFailed)
    }
}
