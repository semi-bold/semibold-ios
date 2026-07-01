import Foundation
import Security

/// Persists and retrieves the person's `AuthSession` in the system Keychain
/// (NO-004 §4.1) so semi:bold can skip the onboarding screen on every
/// subsequent launch.
///
/// Keychain item coordinates (NO-004 §4.1):
/// - service: `"com.semibold.auth"`
/// - account (key): `"session"`
/// - accessibility: `kSecAttrAccessibleAfterFirstUnlock` — allows background
///   restore after the device has been unlocked at least once since boot.
///
/// The session is encoded as JSON (`JSONEncoder`) so both fields survive the
/// round-trip without a separate key for each. A single static instance is
/// enough — there is no mutable state, only Keychain reads and writes.
struct KeychainSessionStore {
    private let service: String
    private let account: String

    /// Creates a store that reads/writes under `service` and `account`.
    ///
    /// The defaults match NO-004 §4.1. Tests may pass different values to
    /// avoid touching the real Keychain item.
    init(
        service: String = "com.semibold.auth",
        account: String = "session"
    ) {
        self.service = service
        self.account = account
    }

    // MARK: - Public interface

    /// Encodes `session` as JSON and writes it to the Keychain, replacing any
    /// previously stored value.
    ///
    /// Silently no-ops if encoding fails — the person will be sent back to
    /// onboarding on the next launch, which is a safe recovery path.
    func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }

        // Try to update an existing item first; if nothing is there yet, add
        // a new one. This is the standard Keychain "upsert" pattern.
        let query = baseQuery()
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    /// Returns the previously stored `AuthSession`, or `nil` if no session
    /// has been saved (first launch) or if the stored data is unreadable.
    func load() -> AuthSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    /// Removes the stored session from the Keychain.
    ///
    /// Called when Apple credential revocation is detected (NO-004 §4.4)
    /// so the person returns to onboarding on the next launch. Silently
    /// no-ops if no session exists.
    func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - Private helpers

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
