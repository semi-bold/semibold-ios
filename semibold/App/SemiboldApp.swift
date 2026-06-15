import SwiftUI

@main
struct SemiboldApp: App {
    /// Shared trigger point for the macOS menu/keyboard-shortcut commands
    /// below — see `AppCommandCenter`.
    @State private var commandCenter = AppCommandCenter()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(commandCenter)
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
