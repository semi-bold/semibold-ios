import SwiftUI

/// The hamburger entry point for the app's navigation drawer
/// (`icon_menu` in `Planning_Nav_1_TopBarFlow`, FLOW-NAV-001), shown in
/// the NavBar's trailing position on `HomeView`, `FolderContentsView`,
/// and `DetailView` so all three apply the same tap target/icon
/// treatment instead of diverging.
///
/// Uses the custom `IconMenu` asset (a template-rendered SVG in
/// `Assets.xcassets`, tinted like an SF Symbol via `.foregroundStyle`) —
/// same convention `BackButtonIcon` follows for `IconHome` — since no SF
/// Symbol matches Figma's `icon_menu` glyph exactly.
///
/// The drawer's actual content is `SidebarDrawerView`
/// (`03-sidebar-drawer`); this button only wires the `isDrawerPresented`
/// toggle each call site owns.
struct MenuButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("IconMenu")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        }
        .foregroundStyle(AppTheme.Colors.Content.primary)
        .frame(width: 40, height: 40)
    }
}
