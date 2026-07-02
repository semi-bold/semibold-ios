import SwiftUI
import AuthenticationServices

@main
struct SemiboldApp: App {
    /// Shared trigger point for the macOS menu/keyboard-shortcut commands
    /// below — see `AppCommandCenter`.
    @State private var commandCenter = AppCommandCenter()

    /// Computed once at launch (NO-004 §3.1's "전체 진입 플로우") — see
    /// `RootLaunchState.resolve` for the full branching logic based on the
    /// Keychain session and iCloud availability.
    @State private var launchState = RootLaunchState.resolve(
        isDatabaseAvailable: DatabaseManager.shared != nil
    )

    /// Holds the Apple user ID returned by Sign in with Apple when iCloud is
    /// not yet available at the time of sign-in (NO-004 §2.2). The 04 brief's
    /// iCloud-setup screen reads this to complete the Keychain write once the
    /// person fixes their iCloud settings.
    @State private var pendingAppleUserID: String = ""

    /// The reason iCloud is not available, populated async when the app lands
    /// on `.iCloudSetupRequired` (NO-004 §5.2). Starts as `.couldNotDetermine`
    /// so the setup screen has a safe default while the async check runs.
    @State private var pendingICloudReason: ICloudUnavailableReason = .couldNotDetermine

    /// Tracks the current scene phase so the app can detect Apple credential
    /// revocation each time it comes back to the foreground (NO-004 §4.4).
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // §15.2 "DB 열기 실패": if the local database couldn't be
            // opened/migrated at launch, there's nothing to read from or
            // write to — show that error instead of any other state.
            switch launchState {
            case .databaseUnavailable:
                DatabaseUnavailableView()
            case .showOnboarding:
                OnboardingView { newState, appleUserID in
                    pendingAppleUserID = appleUserID
                    launchState = newState
                }
            case .iCloudSetupRequired:
                ICloudSetupRequiredView(
                    reason: pendingICloudReason,
                    pendingAppleUserID: pendingAppleUserID
                ) {
                    launchState = .home
                }
                .task {
                    // Resolve the exact reason asynchronously so the guidance
                    // message is accurate; `.couldNotDetermine` is the safe
                    // default while this check is in flight.
                    if let resolved = await ICloudAvailability.unavailableReason() {
                        pendingICloudReason = resolved
                    }
                }
            case .home:
                HomeView()
                    .environment(commandCenter)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            checkAppleCredentialRevocation()
        }
        .commands {
            // macOS keyboard shortcuts (PLANNING/tasks §13.2):
            //   Cmd+N        → New Document
            //   Cmd+Shift+N  → New Folder
            // `CommandGroup(replacing: .newItem)` puts these in the File
            // menu's "New" slot in place of the default (unused) "New
            // Window" item. On iOS, `.commands` content simply has no UI to
            // attach to and is effectively a no-op, so this doesn't need an
            // `#if os(macOS)` guard.
            CommandGroup(replacing: .newItem) {
                Button("New Document") {
                    commandCenter.requestNewDocument()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("New Folder") {
                    commandCenter.requestNewFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }

    // MARK: - Apple credential revocation (NO-004 §4.4)

    /// Checks whether the stored Apple credential has been revoked since the
    /// last launch. Called every time the app returns to the foreground.
    ///
    /// Skipped entirely for local-only sessions (empty `appleUserID`) —
    /// there is no Apple credential to check. On `.revoked` or `.notFound`,
    /// the Keychain session is deleted and the app returns to onboarding;
    /// local data is preserved (NO-004 §2.5).
    private func checkAppleCredentialRevocation() {
        guard let session = KeychainSessionStore().load(),
              !session.appleUserID.isEmpty else {
            // Local session or no session — nothing to check.
            return
        }

        ASAuthorizationAppleIDProvider()
            .getCredentialState(forUserID: session.appleUserID) { state, _ in
                guard state == .revoked || state == .notFound else { return }
                DispatchQueue.main.async {
                    KeychainSessionStore().delete()
                    launchState = .showOnboarding
                }
            }
    }
}
