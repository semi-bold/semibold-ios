import Foundation
import Testing

@testable import semibold

/// Verifies `RootLaunchState.resolve` branches the same way NO-002 §3.1's
/// "최초 실행 플로우" flowchart does, before `HomeView`'s `NavigationStack`
/// is ever entered:
///   - DB unavailable always wins, regardless of sync/iCloud state.
///   - First launch (`sync_mode` unset) + iCloud available → show the
///     consent popup.
///   - First launch + iCloud unavailable → straight to `HomeView`, no
///     popup, no write to `SyncModeStore` (a per-launch check, not a
///     persisted decision).
///   - Not first launch (mode already chosen) → straight to `HomeView`
///     regardless of iCloud availability.
///
/// Each test gets its own ephemeral `UserDefaults` suite, mirroring
/// `SyncModeStoreTests`, so these never touch the real app's saved
/// preference.
struct RootLaunchStateTests {
    private func makeEphemeralSyncModeStore() -> SyncModeStore {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Couldn't create an ephemeral UserDefaults suite for testing")
        }
        return SyncModeStore(userDefaults: defaults)
    }

    @Test("Database unavailable wins over every other check")
    func databaseUnavailableTakesPriority() {
        let store = makeEphemeralSyncModeStore()
        store.setStoredMode(.icloud)

        let state = RootLaunchState.resolve(
            isDatabaseAvailable: false,
            syncModeStore: store,
            fileManager: FakeUbiquityIdentityProvider.signedIn
        )

        #expect(state == .databaseUnavailable)
    }

    @Test("First launch with iCloud available shows the consent popup")
    func firstLaunchWithICloudAvailableShowsConsent() {
        let store = makeEphemeralSyncModeStore()

        let state = RootLaunchState.resolve(
            isDatabaseAvailable: true,
            syncModeStore: store,
            fileManager: FakeUbiquityIdentityProvider.signedIn
        )

        #expect(state == .showICloudConsent)
    }

    @Test("First launch with iCloud unavailable goes straight to HomeView, no popup")
    func firstLaunchWithICloudUnavailableSkipsConsent() {
        let store = makeEphemeralSyncModeStore()

        let state = RootLaunchState.resolve(
            isDatabaseAvailable: true,
            syncModeStore: store,
            fileManager: FakeUbiquityIdentityProvider.signedOut
        )

        #expect(state == .home)
        // The skip is a per-launch check, not a persisted decision —
        // nothing should be written to SyncModeStore just because iCloud
        // happened to be unavailable this time.
        #expect(store.storedMode == nil)
    }

    @Test("Already-answered first launch (mode already stored) goes straight to HomeView")
    func alreadyAnsweredSkipsConsentRegardlessOfICloudAvailability() {
        let store = makeEphemeralSyncModeStore()
        store.setStoredMode(.local)

        let state = RootLaunchState.resolve(
            isDatabaseAvailable: true,
            syncModeStore: store,
            fileManager: FakeUbiquityIdentityProvider.signedIn
        )

        #expect(state == .home)
    }
}
