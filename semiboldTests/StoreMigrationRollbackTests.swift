import CoreData
import Testing

@testable import semibold

/// Confirms the rollback half of `tasks/NO-005.md` §5 "마이그레이션 플로우"
/// ("실패 → 백업 스냅샷으로 롤백 → §15.2 DB 열기 실패 안내") actually runs and
/// actually restores usable data — this feature's AC4 (`.claude/features/
/// 06-migration-rehearsal.md`).
///
/// `StoreMigrationTests`/`RealDeviceMigrationRehearsalTests` both exercise
/// the *successful* migration path; neither ever makes `migrateStoreIfNeeded`
/// fail. Getting a failure to land specifically in the swap/verify step —
/// the only step that calls `restoreBackup` — turns out not to be possible
/// from outside the coordinator without either short-circuiting earlier or
/// jamming the rollback itself (see `StoreMigrationCoordinator
/// .debugSwapFailureInjector`'s doc comment for the two dead ends this ran
/// into: corrupting the source store file only ever surfaces as
/// `sourceModelUnavailable`/`backupFailed` before backup/rollback are even
/// relevant, or — if the corruption instead locks `storeURL` itself so the
/// *swap* fails — the rollback's own swap targets that exact same locked
/// `storeURL` and fails identically, producing `rollbackFailed` (both
/// attempts blocked) rather than the "rollback succeeds" scenario this AC
/// asks for). `DocumentBlockMigrationPolicy` is also deliberately
/// defensive about malformed block content (this feature's brief 05
/// decision) — it degrades to empty/read-only text instead of throwing, so
/// no amount of corrupting a block's `contentJSON` can make the migration
/// step itself fail either.
///
/// So this drives the rollback through `StoreMigrationCoordinator
/// .debugSwapFailureInjector`, a `#if DEBUG`-only fault-injection seam
/// added alongside this test (excluded from Release builds — see that
/// property's doc comment). It makes `migrateStoreIfNeeded` throw at
/// exactly the point a genuine swap-time failure would (e.g. the store's
/// directory losing write access, or a sidecar rename losing a race, mid-
/// swap) — everything downstream of that (the `catch` block, `restoreBackup`
/// copying the real backup back over `storeURL`, the atomic swap into
/// place) is the same, un-mocked production code every other migration
/// test exercises.
struct StoreMigrationRollbackTests {
    // MARK: - Legacy (pre-NO-005) store setup — same pattern as
    // `StoreMigrationTests`/`RealDeviceMigrationRehearsalTests`.

    private enum Fixture {
        static let folderId = "rollback-folder"
        static let folderName = "Rollback Folder"
        static let documentId = "rollback-document"
        static let documentTitle = "Rollback Document"
        static let blockId = "rollback-block"
        static let blockContentJSON = #"{"type":"paragraph","text":[{"text":"Before the incomplete migration"}]}"#
    }

    private func legacyModel() throws -> NSManagedObjectModel {
        let momdURL = try #require(
            Bundle(for: DatabaseManager.self).url(forResource: "SemiboldModel", withExtension: "momd")
        )
        return try #require(
            NSManagedObjectModel(contentsOf: momdURL.appendingPathComponent("SemiboldModel.mom"))
        )
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func openStore(model: NSManagedObjectModel, storeURL: URL) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "SemiboldModel", managedObjectModel: model)
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    /// Builds a small, otherwise-perfectly-migratable pre-NO-005 store — 1
    /// `Folder`, 1 `Document`, 1 `DocumentBlock` — so a later mismatch can
    /// only be explained by the rollback, not by this starting point being
    /// doomed to fail migration on its own (this feature's Decision "01의
    /// 마이그레이션 테스트... 대체하지 않음"; this test's whole point is the
    /// failure/rollback path, not re-proving migration correctness).
    private func seedLegacyStore(at storeURL: URL) throws {
        let container = try openStore(model: try legacyModel(), storeURL: storeURL)
        let context = container.viewContext
        let now = Date()

        let folder = NSEntityDescription.insertNewObject(forEntityName: "Folder", into: context)
        folder.setValue(Fixture.folderId, forKey: "id")
        folder.setValue(Fixture.folderName, forKey: "name")
        folder.setValue(Int64(0), forKey: "sortOrder")
        folder.setValue(now, forKey: "createdAt")
        folder.setValue(now, forKey: "updatedAt")

        let document = NSEntityDescription.insertNewObject(forEntityName: "Document", into: context)
        document.setValue(Fixture.documentId, forKey: "id")
        document.setValue(Fixture.documentTitle, forKey: "title")
        document.setValue(Int64(0), forKey: "sortOrder")
        document.setValue(now, forKey: "createdAt")
        document.setValue(now, forKey: "updatedAt")
        document.setValue(folder, forKey: "folder")

        let block = NSEntityDescription.insertNewObject(forEntityName: "DocumentBlock", into: context)
        block.setValue(Fixture.blockId, forKey: "id")
        block.setValue(Int64(0), forKey: "sortOrder")
        block.setValue(BlockType.paragraph.rawValue, forKey: "type")
        block.setValue(Fixture.blockContentJSON, forKey: "contentJSON")
        block.setValue(now, forKey: "createdAt")
        block.setValue(now, forKey: "updatedAt")
        block.setValue(document, forKey: "document")

        try context.save()
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    /// Reads the store at `storeURL` against the *legacy* (pre-NO-005)
    /// model and confirms it still holds exactly `seedLegacyStore`'s
    /// fixture — i.e. the file is not just "present" but genuinely
    /// openable and unchanged, the same content a person would get back if
    /// this rollback had run for them on their own device.
    private func assertRestoredToOriginalLegacyContent(storeURL: URL) throws {
        let container = try openStore(model: try legacyModel(), storeURL: storeURL)
        let context = container.viewContext

        let folders = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Folder"))
        #expect(folders.count == 1)
        #expect(folders.first?.value(forKey: "id") as? String == Fixture.folderId)
        #expect(folders.first?.value(forKey: "name") as? String == Fixture.folderName)

        let documents = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Document"))
        #expect(documents.count == 1)
        #expect(documents.first?.value(forKey: "id") as? String == Fixture.documentId)
        #expect(documents.first?.value(forKey: "title") as? String == Fixture.documentTitle)

        let blocks = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "DocumentBlock"))
        #expect(blocks.count == 1)
        #expect(blocks.first?.value(forKey: "id") as? String == Fixture.blockId)
        #expect(blocks.first?.value(forKey: "contentJSON") as? String == Fixture.blockContentJSON)

        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    // MARK: - The test

    @Test(
        "An incomplete/failed migration (swap-time failure, after a good backup already exists) rolls back to the original pre-migration store and surfaces through DatabaseManager's real init/openError path"
    )
    func failedMigrationRollsBackAndSurfacesThroughDatabaseManager() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let storeURL = tempDirectory.appendingPathComponent("rollback.sqlite")
        try seedLegacyStore(at: storeURL)

        // Simulates an incomplete migration attempt: the backup step has
        // already captured a good pre-migration snapshot and the custom
        // migration policy has already produced a valid staging store, but
        // the final swap into place fails (e.g. the store's directory
        // loses write access mid-swap) — see `debugSwapFailureInjector`'s
        // doc comment for why this is the only reliable way to land
        // exactly here from a black-box test.
        struct InjectedSwapFailure: Error, LocalizedError {
            var errorDescription: String? { "Simulated: the store's directory lost write access mid-swap" }
        }
        // Reset unconditionally at the end too, as a safety net for any
        // early return/failure above the explicit reset below — this
        // static must never leak into a later test.
        defer { StoreMigrationCoordinator.debugSwapFailureInjector = nil }
        StoreMigrationCoordinator.debugSwapFailureInjector = { InjectedSwapFailure() }

        // Drive the failure through `DatabaseManager.init` directly — the
        // exact call `DatabaseManager.shared` makes and lets throw into its
        // own `catch` block (`private(set) static var openError`) — rather
        // than calling `StoreMigrationCoordinator.migrateStoreIfNeeded` in
        // isolation, so this confirms the real production error-surfacing
        // path, not just the coordinator's own contract.
        var capturedOpenError: Error?
        do {
            _ = try DatabaseManager(storeURL: storeURL, syncEnabled: false)
            Issue.record("Expected DatabaseManager(storeURL:) to throw for an incomplete migration")
        } catch {
            // Mirrors `DatabaseManager.shared`'s catch block exactly:
            // `openError = error; _sharedInstance = nil`.
            capturedOpenError = error
        }
        // The injector's only job was to make *this one* migration attempt
        // fail at the swap step — clear it now so the retry below (and
        // §7's "다음 실행 시 백업 스냅샷에서 재시도") runs against the real,
        // un-mocked coordinator, same as an actual relaunch would.
        StoreMigrationCoordinator.debugSwapFailureInjector = nil

        let migrationError = try #require(capturedOpenError as? StoreMigrationCoordinator.MigrationError)
        guard case .storeSwapFailed = migrationError else {
            Issue.record("Expected .storeSwapFailed (rollback succeeded) but got \(migrationError)")
            return
        }

        // The rollback path actually restored a working, openable store —
        // not just "some file exists at storeURL" — with the exact
        // pre-migration content, not a partial/corrupted one.
        try assertRestoredToOriginalLegacyContent(storeURL: storeURL)

        // A second, un-corrupted attempt succeeds from this restored store
        // — confirming §7 "다음 실행 시 백업 스냅샷에서 재시도" end to end:
        // the person isn't stuck, they can just relaunch.
        let retried = try DatabaseManager(storeURL: storeURL, syncEnabled: false)
        let items = try retried.persistentContainer.viewContext.fetch(DocumentItemEntity.fetchRequest())
        #expect(items.count == 1)
        #expect(items.first?.id == Fixture.blockId)

        // Release the connection before this test's temp directory gets
        // removed above, so SQLite doesn't warn about its files being
        // unlinked out from under a still-open store.
        if let store = retried.persistentContainer.persistentStoreCoordinator.persistentStores.first {
            try? retried.persistentContainer.persistentStoreCoordinator.remove(store)
        }
    }
}
