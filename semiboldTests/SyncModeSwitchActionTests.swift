import Foundation
import Testing

@testable import semibold

/// Verifies `SyncModeSwitchAction` — the decision/action logic behind
/// `SettingsView`'s sync toggle (NO-002 §2.4, §3.2 "설정 전환 플로우"):
/// which confirmation warning applies for a given direction, and whether
/// the actual `DatabaseManager.switchMode` call succeeds.
@MainActor
struct SyncModeSwitchActionTests {
    /// A fake `UbiquityIdentityProviding` that reports a fixed
    /// available/unavailable state, mirroring
    /// `ICloudAvailabilityTests`/`RootLaunchStateTests`'s fakes.
    private struct FakeFileManager: UbiquityIdentityProviding {
        let isAvailable: Bool
        var ubiquityIdentityToken: (NSCoding & NSCopying & NSObjectProtocol)? {
            isAvailable ? NSString("token") : nil
        }
    }

    private func makeEphemeralSyncModeStore() -> SyncModeStore {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Couldn't create an ephemeral UserDefaults suite for testing")
        }
        return SyncModeStore(userDefaults: defaults)
    }

    /// A store location `loadPersistentStores` can't create a SQLite file
    /// at — mirrors `DatabaseManagerSwitchModeTests`'s helper, standing in
    /// for "the new container's store failed to load".
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

    // MARK: - prompt(for:)

    @Test("로컬 → iCloud while iCloud is available asks to confirm the upload warning")
    func localToICloudWhenAvailablePromptsUploadWarning() {
        let prompt = SyncModeSwitchAction.prompt(for: .icloud, fileManager: FakeFileManager(isAvailable: true))

        #expect(prompt == .confirmLocalToICloud)
        #expect(prompt.warningMessage == "기존 로컬 데이터를 iCloud로 업로드합니다.")
    }

    @Test("로컬 → iCloud while iCloud is NOT available skips the warning and asks for iCloud setup guidance")
    func localToICloudWhenUnavailablePromptsGuidance() {
        let prompt = SyncModeSwitchAction.prompt(for: .icloud, fileManager: FakeFileManager(isAvailable: false))

        #expect(prompt == .iCloudUnavailable)
        #expect(prompt.warningMessage == nil)
    }

    @Test("iCloud → 로컬 always asks to confirm the sync-stop warning, regardless of iCloud availability")
    func icloudToLocalPromptsStopWarning() {
        let promptWhenAvailable = SyncModeSwitchAction.prompt(for: .local, fileManager: FakeFileManager(isAvailable: true))
        let promptWhenUnavailable = SyncModeSwitchAction.prompt(for: .local, fileManager: FakeFileManager(isAvailable: false))

        #expect(promptWhenAvailable == .confirmICloudToLocal)
        #expect(promptWhenUnavailable == .confirmICloudToLocal)
        #expect(promptWhenAvailable.warningMessage == "iCloud 동기화가 중단됩니다. 데이터는 이 기기에 유지됩니다.")
    }

    // MARK: - confirmSwitch(to:databaseManager:storeURL:syncModeStore:)

    @Test("A successful confirmed switch returns true and persists the new mode")
    func successfulConfirmedSwitchReturnsTrue() throws {
        let manager = try DatabaseManager(storeURL: nil)
        let syncModeStore = makeEphemeralSyncModeStore()
        syncModeStore.setStoredMode(.icloud)
        let originalContainer = manager.persistentContainer

        let succeeded = SyncModeSwitchAction.confirmSwitch(
            to: .local,
            databaseManager: manager,
            storeURL: nil,
            syncModeStore: syncModeStore
        )

        #expect(succeeded)
        #expect(syncModeStore.storedMode == .local)
        #expect(manager.persistentContainer !== originalContainer)
    }

    @Test("A failed confirmed switch returns false and leaves the stored mode/container untouched")
    func failedConfirmedSwitchReturnsFalse() throws {
        let manager = try DatabaseManager(storeURL: nil)
        let syncModeStore = makeEphemeralSyncModeStore()
        syncModeStore.setStoredMode(.local)
        let originalContainer = manager.persistentContainer
        let unloadableStoreURL = try Self.makeUnloadableStoreURL()

        let succeeded = SyncModeSwitchAction.confirmSwitch(
            to: .icloud,
            databaseManager: manager,
            storeURL: unloadableStoreURL,
            syncModeStore: syncModeStore
        )

        #expect(!succeeded)
        #expect(syncModeStore.storedMode == .local)
        #expect(manager.persistentContainer === originalContainer)
    }

    @Test("Passing a nil DatabaseManager (DB unavailable) returns false without touching anything")
    func nilDatabaseManagerReturnsFalse() {
        let syncModeStore = makeEphemeralSyncModeStore()

        let succeeded = SyncModeSwitchAction.confirmSwitch(
            to: .icloud,
            databaseManager: nil,
            storeURL: nil,
            syncModeStore: syncModeStore
        )

        #expect(!succeeded)
        #expect(syncModeStore.storedMode == nil)
    }
}
