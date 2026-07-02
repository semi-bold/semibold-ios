import SwiftUI

/// The app's settings screen.
///
/// NOTE: The iCloud sync toggle section (NO-002 §3.2) was removed as part
/// of NO-004's runtime-switchMode retirement. The sync UI below is
/// intentionally stubbed out and will be fully replaced in the 05 brief.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            navBar
        }
        .background(AppTheme.Colors.background)
        .toolbar(.hidden)
    }

    // MARK: - Nav bar

    /// `NavBar` (wireframe.py:1056-1061): back label on the left, "설정"
    /// title centered.
    private var navBar: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("설정")
                    .appTextStyle(AppTheme.Typography.body)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.Colors.text1)

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Text("< 돌아가기")
                            .appTextStyle(AppTheme.Typography.body)
                            .foregroundStyle(AppTheme.Colors.primary)
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 52)

            Rectangle()
                .fill(AppTheme.Colors.divider)
                .frame(height: 1)
        }
        .background(AppTheme.Colors.surface)
    }
}

#Preview {
    SettingsView()
        .environment(AppCommandCenter())
}
