import Testing

@testable import semibold

/// Verifies `AccountDataWipe.wipeAll(context:)` — the data-layer half of
/// "탈퇴하기" account deletion (`tasks/NO-008.md` §5.2) — actually purges
/// every folder/document/content row, not just the live (non-soft-deleted)
/// ones. `SemiboldApp.deleteAccount()` (untestable directly here since it
/// lives on a `View`/`App` struct and drives `launchState`) calls this same
/// entry point before its own Keychain-delete/`resetShared()`/
/// `launchState = .showOnboarding` steps, which mirror the already-tested
/// `resetToOnboarding()` precedent — see this project's `05-account-
/// deletion` report for what's verified here vs. by structural inspection.
///
/// `.serialized`: this suite's tests each drive several nested
/// `context.save()` calls in a row (`hardDeleteAll()`'s per-root-entity
/// recursion) against their own in-memory `CoreDataTestStore` — the same
/// "several `NSPersistentContainer` setups/saves racing on `DatabaseManager.
/// model`'s single shared, process-wide `NSManagedObjectModel` instance"
/// concurrency hazard `ContentRepositoriesTests` already documents and
/// serializes its own tests against. Serializing here removes this suite's
/// contribution to that race; full elimination (races with *other* suites'
/// concurrent `CoreDataTestStore` usage) remains that broader, not-yet-done
/// follow-up.
@Suite(.serialized)
struct AccountDataWipeTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    @Test("wipeAll purges a nested folder's document tree — DocumentItem, TextItem, TextMark, MediaItem, and Asset rows")
    func wipeAllPurgesNestedFolderContentTree() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)
        let itemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)
        let textMarkRepository = TextMarkRepository(context: store.context)
        let mediaItemRepository = MediaItemRepository(context: store.context)
        let assetRepository = AssetRepository(context: store.context)

        // A nested folder tree with a document, a text item + mark, and a
        // media item + asset underneath it.
        let rootFolder = try folderRepository.create(Folder(name: "Root"))
        let nestedFolder = try folderRepository.create(Folder(parentId: rootFolder.id, name: "Nested"))
        let nestedDocument = try documentRepository.create(Document(folderId: nestedFolder.id, title: "Nested Doc"))

        let textDocItem = try itemRepository.create(
            DocumentItem(documentId: nestedDocument.id, contentType: "text", orderKey: "0100000000")
        )
        try textItemRepository.create(TextContent(itemId: textDocItem.id, textKind: "paragraph", plainText: "Hello"))
        try textMarkRepository.create(
            TextMark(id: "mark-1", itemId: textDocItem.id, startOffset: 0, endOffset: 5, markType: "bold")
        )

        let asset = try assetRepository.create(
            Asset(id: "asset-1", localPath: "a.jpg", mimeType: "image/jpeg", fileName: "a.jpg")
        )
        let mediaDocItem = try itemRepository.create(
            DocumentItem(documentId: nestedDocument.id, contentType: "media", orderKey: "0200000000")
        )
        try mediaItemRepository.create(MediaContent(itemId: mediaDocItem.id, assetId: asset.id, mediaType: "image"))

        try AccountDataWipe.wipeAll(context: store.context)

        // `find(id:)`/`find(itemId:)` surface soft-deleted rows too, so a
        // `nil` result here means the row was actually purged.
        #expect(try folderRepository.find(id: rootFolder.id) == nil)
        #expect(try folderRepository.find(id: nestedFolder.id) == nil)
        #expect(try documentRepository.find(id: nestedDocument.id) == nil)
        #expect(try itemRepository.find(id: textDocItem.id) == nil)
        #expect(try itemRepository.find(id: mediaDocItem.id) == nil)
        #expect(try textItemRepository.find(itemId: textDocItem.id) == nil)
        #expect(try textMarkRepository.marks(itemId: textDocItem.id).isEmpty)
        #expect(try mediaItemRepository.find(itemId: mediaDocItem.id) == nil)
        #expect(try assetRepository.find(id: asset.id) == nil)
        #expect(try folderRepository.children(of: nil).isEmpty)
    }

    @Test("wipeAll purges a standalone root-level document and its own content")
    func wipeAllPurgesRootLevelDocument() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let itemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        // A root-level document with its own content, outside any folder.
        let rootDocument = try documentRepository.create(Document(title: "Root Doc"))
        let rootDocItem = try itemRepository.create(
            DocumentItem(documentId: rootDocument.id, contentType: "text", orderKey: "0100000000")
        )
        try textItemRepository.create(TextContent(itemId: rootDocItem.id, textKind: "paragraph", plainText: "Top level"))

        try AccountDataWipe.wipeAll(context: store.context)

        #expect(try documentRepository.find(id: rootDocument.id) == nil)
        #expect(try itemRepository.find(id: rootDocItem.id) == nil)
        #expect(try textItemRepository.find(itemId: rootDocItem.id) == nil)
        #expect(try documentRepository.documents(in: nil).isEmpty)
    }

    @Test(
        "wipeAll purges already-soft-deleted root folders/documents too — not just deletedAt-filtered live rows"
    )
    func wipeAllPurgesAlreadySoftDeletedRows() throws {
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)

        // Already soft-deleted before the wipe runs — a real account wipe
        // must catch these too, not just live rows. Nesting a document
        // under the soft-deleted folder also proves the cascade reaches
        // descendants regardless of the folder's own deletedAt state.
        let softDeletedFolder = try folderRepository.create(Folder(name: "Already Deleted Folder"))
        let docInSoftDeletedFolder = try documentRepository.create(
            Document(folderId: softDeletedFolder.id, title: "Doc In Deleted Folder")
        )
        try folderRepository.softDelete(id: softDeletedFolder.id)

        let softDeletedDocument = try documentRepository.create(Document(title: "Already Deleted Doc"))
        try documentRepository.softDelete(id: softDeletedDocument.id)

        try AccountDataWipe.wipeAll(context: store.context)

        // `find(id:)` surfaces soft-deleted rows too, so a `nil` result
        // here means the row was actually purged — not just hidden behind
        // a `deletedAt` filter.
        #expect(try folderRepository.find(id: softDeletedFolder.id) == nil)
        #expect(try documentRepository.find(id: docInSoftDeletedFolder.id) == nil)
        #expect(try documentRepository.find(id: softDeletedDocument.id) == nil)
    }

    @Test("A local-mode session's wipe fully clears its store synchronously, with no iCloud-specific handling")
    func localModeWipeClearsStore() throws {
        // `AccountDataWipe.wipeAll` takes a plain `NSManagedObjectContext`
        // and never branches on sync mode — the same call `SemiboldApp.
        // deleteAccount()` makes for every session. This store stands in
        // for a local-mode session's `local.sqlite`-backed context.
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)

        let folder = try folderRepository.create(Folder(name: "Recipes"))
        let document = try documentRepository.create(Document(title: "Project Plan"))

        try AccountDataWipe.wipeAll(context: store.context)

        #expect(try folderRepository.find(id: folder.id) == nil)
        #expect(try documentRepository.find(id: document.id) == nil)
        #expect(try folderRepository.children(of: nil).isEmpty)
        #expect(try documentRepository.documents(in: nil).isEmpty)
    }

    @Test("An iCloud-mode session's wipe clears its local store the same way, independent of CloudKit propagation")
    func icloudModeWipeClearsLocalStore() throws {
        // There is no CloudKit-backed `CoreDataTestStore` variant to load
        // against in this test target — `DatabaseManagerContainerFactoryTests`
        // already notes actually loading an `NSPersistentCloudKitContainer`
        // isn't feasible without real Apple Developer Console CloudKit
        // setup, and isn't needed here anyway: `AccountDataWipe.wipeAll`
        // operates purely against whichever `NSManagedObjectContext` it's
        // handed, with no branching on `syncEnabled`/session mode, and
        // `DatabaseManagerContainerFactoryTests.bothBranchesShareTheSameModelInstance`
        // already proves the local and iCloud-backed containers share the
        // exact same `SemiboldModel` schema. So this test — using the same
        // in-memory store as the local-mode test above, standing in for an
        // iCloud-mode session's `cloud.sqlite`-backed context — proves the
        // local hard-delete for an iCloud-mode session, which is all this
        // brief's Decisions call for; guaranteeing the CloudKit-side copy
        // is also removed is explicitly out of scope (`tasks/NO-008.md`
        // §5.2, this feature's Open Questions).
        let store = try makeStore()
        let folderRepository = FolderRepository(context: store.context)
        let documentRepository = DocumentRepository(context: store.context)

        let folder = try folderRepository.create(Folder(name: "Recipes"))
        let nestedDocument = try documentRepository.create(Document(folderId: folder.id, title: "Notes"))
        let rootDocument = try documentRepository.create(Document(title: "Project Plan"))

        try AccountDataWipe.wipeAll(context: store.context)

        #expect(try folderRepository.find(id: folder.id) == nil)
        #expect(try documentRepository.find(id: nestedDocument.id) == nil)
        #expect(try documentRepository.find(id: rootDocument.id) == nil)
        #expect(try folderRepository.children(of: nil).isEmpty)
        #expect(try documentRepository.documents(in: nil).isEmpty)
    }
}
