import SwiftUI

/// The compact tooltip menu shown above the drawer's account row
/// (`iOS_SidebarDrawer_AccountMenu`, `Planning_Nav_3_AccountFlow`,
/// FLOW-NAV-003) — the account flow's first step ("어떤 액션인지 선택").
/// Its only two options are "로그아웃" (destructive-red, normal
/// emphasis) and "탈퇴하기" (secondary gray, smaller text).
///
/// The two-tier emphasis is a deliberate Figma decision, not an
/// oversight (`04-account-tooltip-and-alerts`'s Decisions & Deviations):
/// "탈퇴하기"'s stronger, red treatment is reserved for the second-step
/// delete-account alert this tooltip opens, not shown here.
struct AccountActionTooltip: View {
    let onLogoutTapped: () -> Void
    let onDeleteAccountTapped: () -> Void

    /// Horizontal inset of the menu (and its pointer) from the account
    /// row's leading edge, so the pointer roughly lines up with the
    /// row's account icon it points down at.
    private static let leadingInset: CGFloat = AppTheme.Spacing.lg

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Button(action: onLogoutTapped) {
                    Text("로그아웃")
                        .appTextStyle(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.Feedback.danger)
                }
                .buttonStyle(.plain)

                Button(action: onDeleteAccountTapped) {
                    Text("탈퇴하기")
                        .appTextStyle(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.Content.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.Neutral.n700, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

            // Small pointer triangle connecting the menu visually to the
            // account row it's anchored above.
            TooltipPointer()
                .fill(AppTheme.Colors.Neutral.n700)
                .frame(width: 14, height: 7)
                .padding(.leading, Self.leadingInset)
        }
    }
}

/// A downward-pointing triangle for `AccountActionTooltip`'s pointer.
private struct TooltipPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack(alignment: .topLeading) {
        Color(AppTheme.Colors.Neutral.n900).ignoresSafeArea()
        AccountActionTooltip(onLogoutTapped: {}, onDeleteAccountTapped: {})
            .padding(40)
    }
}
