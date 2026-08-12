import Foundation

/// Decides what `SemiboldApp`'s root view should show at launch (NO-004
/// §3.1's "전체 진입 플로우").
///
/// Pulled out of `SemiboldApp` itself so this branching logic has a plain
/// value type that is testable without instantiating SwiftUI's `App`/`Scene`
/// types directly.
enum RootLaunchState: Equatable {
    /// The local database couldn't be opened at launch (§15.2 "DB 열기
    /// 실패") — show `DatabaseUnavailableView` instead of anything else.
    case databaseUnavailable
    /// No Keychain session exists — either first launch or after Apple
    /// credential revocation. Show the onboarding screen so the person can
    /// sign in with Apple or choose local-only mode (NO-004 §2.1/§2.3).
    case showOnboarding
    /// A valid session exists and storage is ready — show `HomeScreen`
    /// directly. Covers both `.local` mode sessions and `.icloud` mode
    /// sessions where iCloud is available right now (NO-004 §3.1).
    case home
    /// A session with mode `.icloud` exists but iCloud is unavailable on
    /// this device at launch — show the iCloud setup guidance screen so
    /// the person can fix their iCloud settings before proceeding
    /// (NO-004 §2.2, §3.1 "iCloud 가용?" branch → No).
    case iCloudSetupRequired

    /// Computes which state the root view should be in right now.
    ///
    /// iCloud availability is deliberately re-checked on every launch
    /// rather than cached: the person may sign in or out of iCloud between
    /// launches, so the check must reflect the current state of the device
    /// at the moment the app starts — not a value baked in from a previous
    /// launch.
    ///
    /// - Parameters:
    ///   - isDatabaseAvailable: Whether `DatabaseManager.shared` loaded
    ///     successfully. Takes priority over every other check — there is
    ///     nothing to read/write from if storage itself failed.
    ///   - sessionStore: Where the person's saved session is read from.
    ///     Defaults to the real `KeychainSessionStore`; tests inject a
    ///     `SessionStoring` fake to control session presence and mode
    ///     without touching the system Keychain (which doesn't work in
    ///     simulator test environments without entitlements).
    ///   - fileManager: The `UbiquityIdentityProviding` iCloud availability
    ///     is checked through. Defaults to `FileManager.default`; tests
    ///     inject a fake to force either state deterministically.
    static func resolve(
        isDatabaseAvailable: Bool,
        sessionStore: any SessionStoring = KeychainSessionStore(),
        fileManager: UbiquityIdentityProviding = FileManager.default
    ) -> RootLaunchState {
        guard isDatabaseAvailable else {
            return .databaseUnavailable
        }
        guard let session = sessionStore.load() else {
            return .showOnboarding
        }
        switch session.mode {
        case .local:
            return .home
        case .icloud:
            return ICloudAvailability.isAvailable(fileManager: fileManager) ? .home : .iCloudSetupRequired
        }
    }
}
