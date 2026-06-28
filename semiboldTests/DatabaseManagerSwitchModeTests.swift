import CoreData
import Foundation
import Testing

@testable import semibold

/// Verifies `DatabaseManager.switchMode(to:storeURL:syncModeStore:)` — the
/// data-handling half of NO-002 §3.2's "설정 전환 플로우" (settings-mode
/// switch flow) and §7's "모드 전환 실패" (mode switch failure) fallback.
///
/// Apple Developer Console setup (Team ID, `semibold.entitlements`) hasn't
/// happened for this app yet, so the iCloud-bound switch direction can only
/// be exercised up to the point where loading its store would actually
/// touch CloudKit — these tests cover the local-only roundtrip end-to-end,
/// and simulate a switch failure with a local container (an unwritable
/// store location) standing in for "the new container's store failed to
/// load", which exercises the same rollback path a failed iCloud connect
/// would.
@MainActor
struct DatabaseManagerSwitchModeTests {
    /// A throwaway `UserDefaults` suite, isolated from both the real app
    /// defaults and other tests' suites.
    private func makeEphemeralDefaults() -> UserDefaults {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Couldn't create an ephemeral UserDefaults suite for testing")
        }
        return defaults
    }

    @Test("A successful switch commits the new mode and starts using the new container")
    func successfulSwitchCommitsNewModeAndContainer() throws {
        let manager = try DatabaseManager(storeURL: nil)
        let syncModeStore = SyncModeStore(userDefaults: makeEphemeralDefaults())
        syncModeStore.setStoredMode(.local)
        let originalContainer = manager.persistentContainer

        try manager.switchMode(to: .local, storeURL: nil, syncModeStore: syncModeStore)

        #expect(syncModeStore.storedMode == .local)
        // The switch built and loaded a brand-new container rather than
        // reusing the original one, even though both are local-only.
        #expect(manager.persistentContainer !== originalContainer)

        // The new container is actually live and usable.
        let folder = FolderEntity(context: manager.persistentContainer.viewContext)
        folder.id = UUID().uuidString
        folder.name = "Switched"
        folder.sortOrder = 0
        folder.createdAt = Date()
        folder.updatedAt = Date()
        try manager.persistentContainer.viewContext.save()
    }

    @Test("A failed switch leaves storedMode unchanged (rollback)")
    func failedSwitchLeavesStoredModeUnchanged() throws {
        let manager = try DatabaseManager(storeURL: nil)
        let syncModeStore = SyncModeStore(userDefaults: makeEphemeralDefaults())
        syncModeStore.setStoredMode(.local)

        let unloadableStoreURL = try Self.makeUnloadableStoreURL()

        #expect(throws: Error.self) {
            try manager.switchMode(to: .icloud, storeURL: unloadableStoreURL, syncModeStore: syncModeStore)
        }

        // Rolled back: the preference still reads as whatever it was
        // before the failed attempt, not the mode that failed to load.
        #expect(syncModeStore.storedMode == .local)
    }

    @Test("A failed switch leaves the original container active and usable")
    func failedSwitchLeavesOriginalContainerFunctional() throws {
        let manager = try DatabaseManager(storeURL: nil)
        let syncModeStore = SyncModeStore(userDefaults: makeEphemeralDefaults())
        syncModeStore.setStoredMode(.local)
        let originalContainer = manager.persistentContainer

        let unloadableStoreURL = try Self.makeUnloadableStoreURL()

        #expect(throws: Error.self) {
            try manager.switchMode(to: .icloud, storeURL: unloadableStoreURL, syncModeStore: syncModeStore)
        }

        // Still pointing at the original container — never swapped out.
        #expect(manager.persistentContainer === originalContainer)

        // The original container's store is still loaded and writable.
        let folder = FolderEntity(context: manager.persistentContainer.viewContext)
        folder.id = UUID().uuidString
        folder.name = "Still here"
        folder.sortOrder = 0
        folder.createdAt = Date()
        folder.updatedAt = Date()
        try manager.persistentContainer.viewContext.save()
    }

    /// A store location `loadPersistentStores` can't create a SQLite file
    /// at: a path nested inside a plain *file* (not a directory), so Core
    /// Data's attempt to create the parent path fails. Stands in for "the
    /// new container's store failed to load" without depending on real
    /// CloudKit connectivity.
    private static func makeUnloadableStoreURL() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try "not a directory".write(
            to: tempDirectory,
            atomically: true,
            encoding: .utf8
        )
        return tempDirectory.appendingPathComponent("nested").appendingPathComponent("semibold.sqlite")
    }
}
