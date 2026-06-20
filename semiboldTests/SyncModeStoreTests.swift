import Foundation
import Testing

@testable import semibold

/// Verifies `SyncModeStore` reads/writes the `sync_mode` `UserDefaults`
/// key per NO-002 §4.3/§6: unset means "first launch", and an explicit
/// `.icloud` choice is only honored when iCloud is actually available.
///
/// Each test gets its own ephemeral `UserDefaults` suite (a fresh
/// `UUID().uuidString` name) instead of `.standard`, so these tests never
/// read or write the real app's saved preference and can't interfere with
/// each other when run in parallel.
struct SyncModeStoreTests {
    /// A throwaway `UserDefaults` suite, isolated from both the real app
    /// defaults and other tests' suites.
    private func makeEphemeralDefaults() -> UserDefaults {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Couldn't create an ephemeral UserDefaults suite for testing")
        }
        return defaults
    }

    @Test("storedMode is nil when sync_mode has never been written (first launch)")
    func unsetKeyReadsAsFirstLaunch() {
        let store = SyncModeStore(userDefaults: makeEphemeralDefaults())

        #expect(store.storedMode == nil)
    }

    @Test("Writing .icloud round-trips through storedMode and the raw UserDefaults string")
    func explicitICloudRoundTrips() {
        let defaults = makeEphemeralDefaults()
        let store = SyncModeStore(userDefaults: defaults)

        store.setStoredMode(.icloud)

        #expect(store.storedMode == .icloud)
        #expect(defaults.string(forKey: SyncModeStore.key) == "icloud")
    }

    @Test("Writing .local round-trips through storedMode and the raw UserDefaults string")
    func explicitLocalRoundTrips() {
        let defaults = makeEphemeralDefaults()
        let store = SyncModeStore(userDefaults: defaults)

        store.setStoredMode(.local)

        #expect(store.storedMode == .local)
        #expect(defaults.string(forKey: SyncModeStore.key) == "local")
    }

    @Test("Writing nil clears the key back to first-launch state")
    func writingNilClearsTheKey() {
        let defaults = makeEphemeralDefaults()
        let store = SyncModeStore(userDefaults: defaults)
        store.setStoredMode(.icloud)

        store.setStoredMode(nil)

        #expect(store.storedMode == nil)
        #expect(defaults.string(forKey: SyncModeStore.key) == nil)
    }

    @Test("effectiveMode is .icloud when storedMode is .icloud and iCloud is available")
    func effectiveModeIsICloudWhenAvailable() {
        let store = SyncModeStore(userDefaults: makeEphemeralDefaults())
        store.setStoredMode(.icloud)

        #expect(store.effectiveMode(fileManager: FakeUbiquityIdentityProvider.signedIn) == .icloud)
    }

    @Test("effectiveMode forces .local when storedMode is .icloud but iCloud is unavailable")
    func effectiveModeForcesLocalWhenICloudUnavailable() {
        let store = SyncModeStore(userDefaults: makeEphemeralDefaults())
        store.setStoredMode(.icloud)

        #expect(store.effectiveMode(fileManager: FakeUbiquityIdentityProvider.signedOut) == .local)
    }

    @Test("effectiveMode is .local when storedMode is .local, regardless of iCloud availability")
    func effectiveModeIsLocalWhenStoredModeIsLocal() {
        let store = SyncModeStore(userDefaults: makeEphemeralDefaults())
        store.setStoredMode(.local)

        #expect(store.effectiveMode(fileManager: FakeUbiquityIdentityProvider.signedIn) == .local)
    }

    @Test("effectiveMode is .local on first launch (no stored mode yet)")
    func effectiveModeIsLocalOnFirstLaunch() {
        let store = SyncModeStore(userDefaults: makeEphemeralDefaults())

        #expect(store.effectiveMode(fileManager: FakeUbiquityIdentityProvider.signedIn) == .local)
    }
}
