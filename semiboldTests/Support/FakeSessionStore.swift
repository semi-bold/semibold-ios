import Foundation

@testable import semibold

/// An in-memory `SessionStoring` fake for `RootLaunchState` tests.
///
/// `KeychainSessionStore` writes to the system Keychain, which is not
/// reliably accessible in simulator test environments without a signing
/// identity and entitlements. This fake stores a session value in memory so
/// `RootLaunchState.resolve` tests can control the "session present / absent"
/// and "session mode" branches without depending on real Keychain behaviour —
/// mirrors the `FakeUbiquityIdentityProvider` pattern used for iCloud
/// availability checks.
struct FakeSessionStore: SessionStoring {
    private let session: AuthSession?

    /// A store that reports no session (simulates first launch or after
    /// credential revocation).
    static let noSession = FakeSessionStore(session: nil)

    /// A store that reports a saved local-only session.
    static let localSession = FakeSessionStore(
        session: AuthSession(appleUserID: "", mode: .local)
    )

    /// A store that reports a saved iCloud session.
    static let icloudSession = FakeSessionStore(
        session: AuthSession(appleUserID: "fake-apple-user-id", mode: .icloud)
    )

    private init(session: AuthSession?) {
        self.session = session
    }

    func load() -> AuthSession? {
        session
    }
}
