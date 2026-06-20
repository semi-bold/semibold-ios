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

    /// Bridges `launchState`'s `.showICloudConsent` case to
    /// `.fullScreenCover(isPresented:)`'s `Binding<Bool>` shape.
    ///
    /// Dismissing without an explicit "동기화 사용"/"나중에" answer (e.g.
    /// swiping away) falls back to `.home` rather than re-presenting —
    /// this item only wires up show/hide; persisting a "나중에"-equivalent
    /// choice on dismissal isn't decided here and lands with the button
    /// actions (this brief's next acceptance-criteria item).
    private var isShowingICloudConsent: Binding<Bool> {
        Binding(
            get: { launchState == .showICloudConsent },
            set: { isPresented in
                if !isPresented {
                    launchState = .home
                }
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            // §15.2 "DB 열기 실패": if the local database couldn't be
            // opened/migrated at launch, there's nothing to read from or
            // write to — show that error instead of any other state.
            switch launchState {
            case .databaseUnavailable:
                DatabaseUnavailableView()
            case .showICloudConsent, .home:
                // The consent popup is decided and shown *before*
                // `HomeView`'s `NavigationStack` is entered (Decisions &
                // Deviations, `.claude/features/03-icloud-onboarding.md`)
                // — it sits as a full-screen layer over `HomeView` rather
                // than gating which view is constructed.
                HomeView()
                    .environment(commandCenter)
                    .fullScreenCover(isPresented: isShowingICloudConsent) {
                        ICloudConsentView()
                    }
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
