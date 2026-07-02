import SwiftUI

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

    var body: some Scene {
        WindowGroup {
            // §15.2 "DB 열기 실패": if the local database couldn't be
            // opened/migrated at launch, there's nothing to read from or
            // write to — show that error instead of any other state.
            switch launchState {
            case .databaseUnavailable:
                DatabaseUnavailableView()
            case .showOnboarding:
                // Placeholder — the real OnboardingView is wired in the
                // 03 brief. Showing EmptyView here avoids a crash while
                // keeping the branching logic in place.
                EmptyView()
            case .iCloudSetupRequired:
                // Placeholder — the real iCloudSetupRequiredView is wired
                // in the 04 brief. Showing EmptyView here avoids a crash
                // while keeping the branching logic in place.
                EmptyView()
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
