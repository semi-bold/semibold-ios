import Foundation

/// The two modes in which semi:bold can operate, chosen by the person at
/// first launch and stored in the Keychain (NO-004 §4.1).
///
/// - `icloud`: The person signed in with Apple; data syncs through
///   `NSPersistentCloudKitContainer`.
/// - `local`: The person chose to stay local-only; data lives in
///   `NSPersistentContainer` on this device only.
enum SessionMode: String, Codable {
    case icloud
    case local
}

/// The information semi:bold keeps in the Keychain between launches so the
/// person is never asked to sign in again (NO-004 §4.1).
///
/// `appleUserID` is the opaque user identifier returned by Sign in with
/// Apple (`ASAuthorizationAppleIDCredential.user`). It is an empty string
/// when `mode` is `.local` — the person never signed in with Apple, so
/// there is no user ID to store.
struct AuthSession: Codable, Equatable {
    /// The opaque Apple user identifier, or `""` for local-only sessions.
    let appleUserID: String
    /// Whether data syncs through iCloud or stays local to this device.
    let mode: SessionMode
}
