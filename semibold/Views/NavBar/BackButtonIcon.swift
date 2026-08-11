import SwiftUI

/// Renders `FolderBackButtonLabel`'s icon — shared by `FolderContentsView`
/// and `DetailView`'s back buttons (`Planning_6_FolderNavigationFlow`
/// callout ①) so both screens' icon-only back button (see
/// `FolderBackButtonLabel.iconName`'s doc comment) look and size the same.
///
/// `.root` uses the custom `IconHome` asset (a template-rendered SVG in
/// `Assets.xcassets`, tinted like an SF Symbol via `.foregroundStyle`)
/// rather than the system `house.fill` glyph, so the app icon isn't the
/// only branded touch — `.parentFolder` still uses the system
/// `chevron.left` symbol.
struct BackButtonIcon: View {
    let label: FolderBackButtonLabel

    var body: some View {
        Group {
            switch label {
            case .root:
                Image("IconHome")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            case .parentFolder:
                Image(systemName: label.iconName)
                    .appTextStyle(AppTheme.Typography.title)
            }
        }
        .foregroundStyle(AppTheme.Colors.accent)
        .frame(width: 24, height: 24)
    }
}
