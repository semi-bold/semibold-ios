import Foundation
import Testing

@testable import semibold

/// Verifies `KeychainSessionStore` correctly persists and retrieves `AuthSession`
/// values in the Keychain (NO-004 §4.1).
///
/// Each test suite creates its own unique Keychain service name so that runs
/// never share state — equivalent to the ephemeral `UserDefaults` pattern used
/// in `SyncModeStoreTests`. After each test the item is explicitly deleted to
/// keep the test Keychain tidy, even on simulators where Keychain state can
/// persist between test runs.
struct KeychainSessionStoreTests {
    /// Returns a fresh store whose Keychain item is isolated from every other
    /// test invocation (and from the real app's `"com.semibold.auth"` item).
    private func makeStore() -> KeychainSessionStore {
        KeychainSessionStore(
            service: "com.semibold.auth.test.\(UUID().uuidString)",
            account: "session"
        )
    }

    // MARK: - save → load round-trip

    @Test("save → load round-trips an iCloud session")
    func saveAndLoadICloudSession() {
        let store = makeStore()
        defer { store.delete() }

        let session = AuthSession(appleUserID: "fake-apple-user-id", mode: .icloud)
        store.save(session)

        let loaded = store.load()

        #expect(loaded == session)
        #expect(loaded?.appleUserID == "fake-apple-user-id")
        #expect(loaded?.mode == .icloud)
    }

    @Test("save → load round-trips a local session (empty appleUserID)")
    func saveAndLoadLocalSession() {
        let store = makeStore()
        defer { store.delete() }

        let session = AuthSession(appleUserID: "", mode: .local)
        store.save(session)

        let loaded = store.load()

        #expect(loaded == session)
        #expect(loaded?.appleUserID == "")
        #expect(loaded?.mode == .local)
    }

    @Test("save overwrites a previously stored session")
    func saveOverwritesPreviousSession() {
        let store = makeStore()
        defer { store.delete() }

        let first = AuthSession(appleUserID: "first-user", mode: .icloud)
        let second = AuthSession(appleUserID: "", mode: .local)

        store.save(first)
        store.save(second)

        #expect(store.load() == second)
    }

    // MARK: - delete followed by load == nil

    @Test("load returns nil when no session has been saved")
    func loadReturnsNilWithNoSession() {
        let store = makeStore()
        // No save call — store is empty.
        #expect(store.load() == nil)
    }

    @Test("delete followed by load returns nil")
    func deleteThenLoadIsNil() {
        let store = makeStore()

        let session = AuthSession(appleUserID: "some-user", mode: .icloud)
        store.save(session)

        // Confirm it was written before testing delete.
        #expect(store.load() != nil)

        store.delete()

        #expect(store.load() == nil)
    }

    @Test("delete on an empty store does not crash")
    func deleteOnEmptyStoreIsHarmless() {
        let store = makeStore()
        // Should silently no-op.
        store.delete()
        #expect(store.load() == nil)
    }
}
