import SwiftUI

@main
struct SemiboldApp: App {
    /// Shared trigger point for the macOS menu/keyboard-shortcut commands
    /// below — see `AppCommandCenter`.
    @State private var commandCenter = AppCommandCenter()

    /// Computed once at launch (NO-002 §3.1's "최초 실행 플로우") — see
    /// `RootLaunchState.resolve` for why iCloud availability is checked
    /// fresh on every launch rather than cached alongside `sync_mode`.
    @State private var launchState = RootLaunchState.resolve(
        isDatabaseAvailable: DatabaseManager.shared != nil
    )

    /// Handles "동기화 사용" (`sync: true`) / "나중에" (`sync: false`) from
    /// `ICloudConsentView` (callouts ③④): persists `sync_mode` and
    /// switches `DatabaseManager.shared`'s container via
    /// `ICloudConsentChoice.apply`, then advances `launchState` to `.home`
    /// — which is what actually constructs `HomeView` for the first time
    /// (see `body` below) — regardless of whether the switch itself
    /// succeeded (see `ICloudConsentChoice`'s doc comment for why a
    /// failure shouldn't leave the person stuck on this screen).
    private func respondToConsent(sync: Bool) {
        ICloudConsentChoice.apply(
            sync: sync,
            databaseManager: DatabaseManager.shared,
            storeURL: DatabaseManager.defaultStoreURL()
        )
        launchState = .home
    }

    var body: some Scene {
        WindowGroup {
            // §15.2 "DB 열기 실패": if the local database couldn't be
            // opened/migrated at launch, there's nothing to read from or
            // write to — show that error instead of any other state.
            switch launchState {
            case .databaseUnavailable:
                DatabaseUnavailableView()
            case .showICloudConsent:
                // `HomeView` is deliberately NOT constructed here.
                // `ICloudConsentChoice.apply` (driven by the buttons
                // below) may switch `DatabaseManager.shared`'s container
                // before the person ever reaches `HomeView` — constructing
                // `HomeViewModel`'s repositories only once `launchState`
                // becomes `.home` guarantees they resolve whichever
                // container is active *after* that switch, never a stale
                // pre-switch one (Decisions & Deviations,
                // `.claude/features/03-icloud-onboarding.md`).
                // `ICloudConsentView` already paints its own full-screen
                // dim overlay, so it can stand alone as the only thing on
                // screen.
                ICloudConsentView(
                    onUseSync: { respondToConsent(sync: true) },
                    onUseLocalOnly: { respondToConsent(sync: false) }
                )
            case .home:
                HomeView()
                    .environment(commandCenter)
            }
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
}
