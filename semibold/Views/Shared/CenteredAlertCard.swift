import SwiftUI

/// A custom centered alert card — title, message, and two attached
/// buttons in one rounded card — reused by the drawer's logout and
/// delete-account popups (`iOS_SidebarDrawer_LogoutAlert` /
/// `iOS_SidebarDrawer_DeleteAccountAlert`, `Planning_Nav_3_AccountFlow`,
/// FLOW-NAV-003).
///
/// Deliberately not SwiftUI's native `.alert`/`.confirmationDialog` —
/// `tasks/NO-008.md` §3.3 splits the account flow into a first-step
/// tooltip (pick an action) and a second-step popup like this one
/// (confirm that action's specific consequences), a two-step structure
/// the native, single-sheet `.confirmationDialog` can't express. Both
/// popups share this exact card chrome so that split doesn't duplicate
/// the visual shape between them.
struct CenteredAlertCard: View {
    let title: String
    let message: String
    let cancelTitle: String
    let confirmTitle: String
    /// Whether the confirm button reads as a destructive action (red) —
    /// `true` for "로그아웃"/"탈퇴하기" in iCloud-mode/delete-account
    /// contexts, `false` for the local-mode "Apple로 로그인" variant.
    var isConfirmDestructive: Bool = true
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: AppTheme.Spacing.sm) {
                Text(title)
                    .appTextStyle(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.Content.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .appTextStyle(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.Content.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.md)

            Rectangle()
                .fill(AppTheme.Colors.Stroke.divider)
                .frame(height: 1)

            HStack(spacing: 0) {
                Button(action: onCancel) {
                    Text(cancelTitle)
                        .appTextStyle(AppTheme.Typography.button)
                        .foregroundStyle(AppTheme.Colors.Content.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(AppTheme.Colors.Stroke.divider)
                    .frame(width: 1)

                Button(action: onConfirm) {
                    Text(confirmTitle)
                        .appTextStyle(AppTheme.Typography.button)
                        .foregroundStyle(
                            isConfirmDestructive ? AppTheme.Colors.Feedback.danger : AppTheme.Colors.accent
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 280)
        .background(AppTheme.Colors.Neutral.n800, in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.4).ignoresSafeArea()
        CenteredAlertCard(
            title: "로그아웃",
            message: "로그아웃하면 이 기기에서 iCloud 동기화가 중단됩니다. 데이터는 iCloud에 유지됩니다.",
            cancelTitle: "취소",
            confirmTitle: "로그아웃",
            onCancel: {},
            onConfirm: {}
        )
    }
}
