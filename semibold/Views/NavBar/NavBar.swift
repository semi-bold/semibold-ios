import SwiftUI

/// The layout-composition layer for every screen's top bar — the shared
/// chrome (fixed 52pt content row, horizontal padding, 1px divider, n800
/// background) that `HomeView`/`FolderContentsView`/`DetailView` used to
/// each hand-roll separately with near-identical `VStack`/`HStack` code.
///
/// Screens plug in only what actually differs between them via three
/// slots — `leading` (back button or wordmark), `center` (an optional
/// title overlay, e.g. a folder's name), and `trailingExtra` (any
/// trailing content that sits before the menu button, e.g. `DetailView`'s
/// export button) — while the trailing-most `MenuButton` (opens
/// `SidebarDrawerView`) is always present, since every screen's NavBar
/// has one (`Planning_Nav_1_TopBarFlow`, FLOW-NAV-001).
///
/// This intentionally does not attempt a route-aware/global mechanism
/// (there's no SwiftUI equivalent of reading "the current path" from
/// anywhere in the tree the way a web router hook would) — each screen
/// still explicitly declares its own slot content, the same way it would
/// declare `ToolbarItem`s with SwiftUI's native `.toolbar`. This is
/// purely about not re-typing the shared chrome three times.
struct NavBar<Leading: View, Center: View, TrailingExtra: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var center: () -> Center
    @ViewBuilder var trailingExtra: () -> TrailingExtra
    let onMenuTapped: () -> Void

    init(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder center: @escaping () -> Center = { EmptyView() },
        @ViewBuilder trailingExtra: @escaping () -> TrailingExtra = { EmptyView() },
        onMenuTapped: @escaping () -> Void
    ) {
        self.leading = leading
        self.center = center
        self.trailingExtra = trailingExtra
        self.onMenuTapped = onMenuTapped
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                center()

                HStack(spacing: AppTheme.Spacing.sm) {
                    leading()
                    Spacer()
                    trailingExtra()
                    MenuButton(action: onMenuTapped)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 52)

            Rectangle()
                .fill(AppTheme.Colors.Stroke.divider)
                .frame(height: 1)
        }
        .background(AppTheme.Colors.Neutral.n800)
    }
}
