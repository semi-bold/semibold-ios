import Foundation
import Testing

@testable import semibold

/// Verifies `ICloudConsentChoice.apply` — the action behind
/// `ICloudConsentView`'s "동기화 사용"/"나중에" buttons (NO-002 §3.1
/// callouts ③④): persisting `sync_mode` and switching
/// `DatabaseManager`'s container to match.
///
/// Each test uses a throwaway in-memory `DatabaseManager` and an
/// ephemeral `UserDefaults` suite, mirroring
/// `DatabaseManagerSwitchModeTests`/`SyncModeStoreTests`, so these never
/// touch the real on-disk store or the app's real saved preference.
///
/// Apple Developer Console setup (Team ID, `semibold.entitlements`)
/// hasn't happened for this app yet (see `DatabaseManager.makeContainer`'s
/// doc comment), so even an in-memory `NSPersistentCloudKitContainer`
/// fails to load its store here — `loadPersistentStores` surfaces a
/// CloudKit connectivity error synchronously. That means "동기화 사용"
/// (`sync: true`) exercises `ICloudConsentChoice`'s *failure* fallback
/// path in this test environment, not the success path — which is
/// actually the right thing to verify pre-entitlements: the fallback
/// behavior is exactly what currently happens for real if someone taps
/// "동기화 사용" today. The success path (`switchMode` actually committing
/// `.icloud`) is covered indirectly by
/// `DatabaseManagerSwitchModeTests`/`SyncModeStoreTests` exercising
/// `switchMode`/`setStoredMode` directly with mode values, independent of
/// whether the underlying container can load.
@MainActor
struct ICloudConsentChoiceTests {
    private func makeEphemeralSyncModeStore() -> SyncModeStore {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Couldn't create an ephemeral UserDefaults suite for testing")
        }
        return SyncModeStore(userDefaults: defaults)
    }

    @Test("\"동기화 사용\" (sync: true) falls back to .local pre-entitlements, since the CloudKit container can't load yet")
    func useSyncFallsBackToLocalPreEntitlements() throws {
        let manager = try DatabaseManager(storeURL: nil)
        let syncModeStore = makeEphemeralSyncModeStore()
        let originalContainer = manager.persistentContainer

        ICloudConsentChoice.apply(
            sync: true,
            databaseManager: manager,
            storeURL: nil,
            syncModeStore: syncModeStore
        )

        // See this file's doc comment: without Developer Console
        // entitlements, loading the CloudKit container fails, so
        // `switchMode` rolls back and `ICloudConsentChoice` persists
        // `.local` to match the container that's actually still active.
        #expect(syncModeStore.storedMode == .local)
        #expect(manager.persistentContainer === originalContainer)
    }

    @Test("\"나중에\" (sync: false) persists sync_mode = .local and switches the container")
    func useLocalOnlyPersistsLocalMode() throws {
        let manager = try DatabaseManager(storeURL: nil)
        let syncModeStore = makeEphemeralSyncModeStore()
        let originalContainer = manager.persistentContainer

        ICloudConsentChoice.apply(
            sync: false,
            databaseManager: manager,
            storeURL: nil,
            syncModeStore: syncModeStore
        )

        #expect(syncModeStore.storedMode == .local)
        #expect(manager.persistentContainer !== originalContainer)
    }

    @Test("A failed \"동기화 사용\" attempt falls back to persisting .local, matching the rolled-back container")
    func failedUseSyncFallsBackToLocal() throws {
        let manager = try DatabaseManager(storeURL: nil)
        let syncModeStore = makeEphemeralSyncModeStore()
        let originalContainer = manager.persistentContainer
        let unloadableStoreURL = try Self.makeUnloadableStoreURL()

        ICloudConsentChoice.apply(
            sync: true,
            databaseManager: manager,
            storeURL: unloadableStoreURL,
            syncModeStore: syncModeStore
        )

        // switchMode rolled back internally (kept using the original
        // container) — sync_mode should reflect that reality rather than
        // the iCloud mode that failed to load.
        #expect(syncModeStore.storedMode == .local)
        #expect(manager.persistentContainer === originalContainer)
    }

    @Test("Passing a nil DatabaseManager (DB unavailable at launch) is a no-op")
    func nilDatabaseManagerIsANoOp() {
        let syncModeStore = makeEphemeralSyncModeStore()

        ICloudConsentChoice.apply(
            sync: true,
            databaseManager: nil,
            storeURL: nil,
            syncModeStore: syncModeStore
        )

        #expect(syncModeStore.storedMode == nil)
    }

    /// A store location `loadPersistentStores` can't create a SQLite file
    /// at — mirrors `DatabaseManagerSwitchModeTests`'s helper, standing in
    /// for "the new container's store failed to load" without depending
    /// on real CloudKit connectivity.
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
