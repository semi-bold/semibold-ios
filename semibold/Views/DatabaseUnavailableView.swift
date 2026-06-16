import SwiftUI

/// Full-screen fallback shown instead of `HomeView` when the local
/// database couldn't be opened at launch (§15.2 "DB 열기 실패").
///
/// semi:bold stores everything in one on-device SQLite file
/// (`DatabaseManager`). If that file can't be opened or migrated — e.g.
/// the device is out of disk space, or the file is corrupted — there's no
/// folder/document list to show. Rather than crashing outright, the app
/// shows this screen with §15.2's exact message so the user at least sees
/// why nothing loaded, instead of the app simply disappearing.
///
/// No `Screen_*`/`Planning_N_*Flow` artboard defines this state (checked
/// `wireframe.py`/`planning.py`/`atoms.py` — every screen assumes a working
/// database), so this reuses `HomeView`'s background/typography tokens for
/// a centered message rather than a dedicated layout.
struct DatabaseUnavailableView: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .appTextStyle(AppTheme.Typography.heading1)
                .foregroundStyle(AppTheme.Colors.error)

            Text(AppErrorMessages.databaseUnavailable)
                .appTextStyle(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.text1)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.background)
    }
}

#Preview {
    DatabaseUnavailableView()
}
