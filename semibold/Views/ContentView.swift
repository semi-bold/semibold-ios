import SwiftUI

/// Placeholder root view — replaced by the real screens
/// (e.g. Screen_Home → HomeView) per CLAUDE.md §1.
///
/// Also serves as a smoke test that `AppTheme` is wired up correctly:
/// every spacing, color, and typography value below comes from the
/// design-token catalog rather than being hardcoded.
struct ContentView: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "doc.text")
                .font(.system(size: AppTheme.Spacing.xxxl))
                .foregroundStyle(AppTheme.Colors.primary)
            Text("semi:bold")
                .appTextStyle(AppTheme.Typography.heading1)
                .foregroundStyle(AppTheme.Colors.text1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.background)
    }
}

#Preview {
    ContentView()
}
