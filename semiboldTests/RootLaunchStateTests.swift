import Foundation
import Testing

@testable import semibold

/// Verifies `RootLaunchState.resolve` branches the same way NO-004 §3.1's
/// "전체 진입 플로우" flowchart does, before `HomeView`'s `NavigationStack`
/// is ever entered:
///   - DB unavailable always wins, regardless of session / iCloud state.
///   - No Keychain session → `.showOnboarding`.
///   - Session with mode `.local` → `.home`.
///   - Session with mode `.icloud` + iCloud available → `.home`.
///   - Session with mode `.icloud` + iCloud unavailable → `.iCloudSetupRequired`.
///
/// Each test injects a `FakeSessionStore` instead of `KeychainSessionStore`
/// so these never touch the real system Keychain (which requires signing
/// entitlements not available in the simulator test environment).
struct RootLaunchStateTests {
    @Test("Database unavailable takes priority over every other check")
    func databaseUnavailableTakesPriority() {
        let state = RootLaunchState.resolve(
            isDatabaseAvailable: false,
            sessionStore: FakeSessionStore.icloudSession,
            fileManager: FakeUbiquityIdentityProvider.signedIn
        )

        #expect(state == .databaseUnavailable)
    }

    @Test("No session leads to onboarding (first launch or after credential revocation)")
    func noSessionShowsOnboarding() {
        let state = RootLaunchState.resolve(
            isDatabaseAvailable: true,
            sessionStore: FakeSessionStore.noSession,
            fileManager: FakeUbiquityIdentityProvider.signedIn
        )

        #expect(state == .showOnboarding)
    }

    @Test("Local-mode session goes straight to HomeView")
    func localSessionGoesHome() {
        let state = RootLaunchState.resolve(
            isDatabaseAvailable: true,
            sessionStore: FakeSessionStore.localSession,
            fileManager: FakeUbiquityIdentityProvider.signedIn
        )

        #expect(state == .home)
    }

    @Test("iCloud-mode session with iCloud available goes straight to HomeView")
    func icloudSessionWithICloudAvailableGoesHome() {
        let state = RootLaunchState.resolve(
            isDatabaseAvailable: true,
            sessionStore: FakeSessionStore.icloudSession,
            fileManager: FakeUbiquityIdentityProvider.signedIn
        )

        #expect(state == .home)
    }

    @Test("iCloud-mode session with iCloud unavailable shows the iCloud setup screen")
    func icloudSessionWithICloudUnavailableShowsSetupRequired() {
        let state = RootLaunchState.resolve(
            isDatabaseAvailable: true,
            sessionStore: FakeSessionStore.icloudSession,
            fileManager: FakeUbiquityIdentityProvider.signedOut
        )

        #expect(state == .iCloudSetupRequired)
    }

    @Test("Local-mode session goes to HomeView regardless of iCloud availability")
    func localSessionGoesHomeEvenWhenICloudUnavailable() {
        let state = RootLaunchState.resolve(
            isDatabaseAvailable: true,
            sessionStore: FakeSessionStore.localSession,
            fileManager: FakeUbiquityIdentityProvider.signedOut
        )

        #expect(state == .home)
    }
}
