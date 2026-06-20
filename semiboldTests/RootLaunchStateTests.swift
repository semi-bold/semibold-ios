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

    /// End-to-end regression for this brief's last acceptance criterion:
    /// "한 번 응답한 이후에는 앱을 재실행해도 팝업이 다시 표시되지 않음"
    /// (once answered, the popup never shows again on a later relaunch).
    ///
    /// The tests above exercise `resolve` against a `SyncModeStore` that's
    /// already pre-seeded via `setStoredMode` directly, which only proves
    /// `resolve`'s branching logic is correct *given* a stored value — it
    /// doesn't prove the value actually survives from one launch to the
    /// next. This test instead drives the real write path
    /// (`ICloudConsentChoice.apply`, what `SemiboldApp` calls when a button
    /// is tapped) on a simulated "launch 1", then constructs a brand new
    /// `SyncModeStore`/`RootLaunchState.resolve` call — as `SemiboldApp`
    /// would on a fresh process start — backed by the *same* underlying
    /// `UserDefaults` suite, simulating "launch 2" after the app was fully
    /// relaunched.
    @MainActor
    @Test("Responding once means a later relaunch never shows the consent popup again")
    func respondingOnceSkipsConsentOnEveryLaterLaunch() throws {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Couldn't create an ephemeral UserDefaults suite for testing")
        }

        // Launch 1: first launch, iCloud available, popup shown.
        let launch1Store = SyncModeStore(userDefaults: defaults)
        let launch1State = RootLaunchState.resolve(
            isDatabaseAvailable: true,
            syncModeStore: launch1Store,
            fileManager: FakeUbiquityIdentityProvider.signedIn
        )
        #expect(launch1State == .showICloudConsent)

        // The person taps "나중에" — this is the exact call SemiboldApp
        // makes from ICloudConsentView's onUseLocalOnly closure.
        let manager = try DatabaseManager(storeURL: nil)
        ICloudConsentChoice.apply(
            sync: false,
            databaseManager: manager,
            storeURL: nil,
            syncModeStore: launch1Store
        )

        // Launch 2: simulate a full app relaunch by building a fresh
        // SyncModeStore over the SAME UserDefaults suite (not reusing
        // launch1Store), exactly like SemiboldApp constructing a brand new
        // SyncModeStore() at process start reading from .standard.
        let launch2Store = SyncModeStore(userDefaults: defaults)
        let launch2State = RootLaunchState.resolve(
            isDatabaseAvailable: true,
            syncModeStore: launch2Store,
            fileManager: FakeUbiquityIdentityProvider.signedIn
        )

        #expect(launch2State != .showICloudConsent)
        #expect(launch2State == .home)
    }
}
