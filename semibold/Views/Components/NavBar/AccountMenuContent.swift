import SwiftUI

/// The account row's menu — presented via `.popover(isPresented:)` from
/// `SidebarDrawerView`'s account row (`Planning_Nav_3_AccountFlow`,
/// FLOW-NAV-003; `iOS_SidebarDrawer_AccountSheet` /
/// `iPadOS_SidebarDrawer_AccountMenu`).
///
/// Deliberately just the content, not the presentation container — the
/// system's own `.popover` handles the container, and its default
/// per-size-class adaptation is used as-is (not overridden with
/// `.presentationCompactAdaptation`): iPad (regular size class) floats
/// this as a small anchored card with an arrow pointing at the account
/// row, iPhone (compact size class) automatically adapts it into a
/// bottom sheet instead. Both are the platform's own default behavior for
/// `.popover`, not a custom-built drawer/tooltip — the previous
/// hand-rolled `alignmentGuide`-positioned tooltip card is what this
/// replaces, since its position never reliably tracked the account row
/// (it measured only its own size, never the row's actual on-screen
/// frame).
///
/// Shows the account's real sync-mode status — no name/email/avatar
/// exists in this app's data model to show instead. Sign in with Apple
/// only ever hands the app an email/full name once, at the very first
/// consent screen for a given (app, Apple ID) pair; every later sign-in
/// returns `nil` for both, and there is no API to fetch them again later.
/// This app's `AuthSession` also doesn't currently capture them even at
/// that first opportunity — surfacing a real Apple ID here would need
/// that captured and persisted first, and still wouldn't backfill for
/// anyone who already signed in before that capture existed.
///
/// The two action rows are equal size, differentiated only by color —
/// "로그아웃" (or "Apple 로그인으로 전환" in local mode, matching the
/// second-step alert's own copy) in the default text color, "탈퇴하기" in
/// destructive red — the common-service convention (e.g. Notion, Slack's
/// account menus), not the previous two-tier size+color emphasis.
struct AccountMenuContent: View {
    let onLogoutTapped: () -> Void
    let onDeleteAccountTapped: () -> Void

    /// Local mode has no active cloud session to log out of, so the first
    /// row reads "Apple 로그인으로 전환" instead — matching
    /// `SidebarDrawerView.logoutAlertOverlay`'s existing `isICloud`
    /// branching for the exact same reason.
    private var isICloud: Bool {
        KeychainSessionStore().load()?.mode == .icloud
    }

    private static let rowHeight: CGFloat = 52
    private static let dividerHeight: CGFloat = 1

    /// Extra breathing room above `statusRow` — without this, the first
    /// row sat almost flush against the system's drag indicator on the
    /// iPhone sheet fallback (`presentationDragIndicator` reserves its own
    /// strip above the content but doesn't add a gap below itself).
    private static let topInset: CGFloat = AppTheme.Spacing.md

    /// This view's total intrinsic height (top inset + status row + 2
    /// dividers + 2 action rows) — used to pin the iPhone sheet fallback
    /// to a compact `.presentationDetents([.height(...)])` instead of the
    /// system default `.large` (full screen), which is what was actually
    /// causing the sheet to cover the whole screen with this content
    /// stranded in the middle of it rather than pinned to the bottom edge.
    static let contentHeight: CGFloat = topInset + rowHeight * 3 + dividerHeight * 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusRow
            divider
            actionRow(
                title: isICloud ? "로그아웃" : "Apple 로그인으로 전환",
                color: AppTheme.Colors.Content.primary,
                action: onLogoutTapped
            )
            divider
            actionRow(
                title: "탈퇴하기",
                color: AppTheme.Colors.Feedback.danger,
                action: onDeleteAccountTapped
            )
        }
        .padding(.top, Self.topInset)
        .frame(idealWidth: 260)
        .background(AppTheme.Colors.Neutral.n700)
    }

    /// Non-interactive — states what's actually true about this session
    /// rather than an invented account identity.
    private var statusRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "person.circle")
                .foregroundStyle(AppTheme.Colors.Content.secondary)
                .frame(width: 22, height: 22)

            Text(isICloud ? "iCloud 동기화 중" : "로컬 전용")
                .appTextStyle(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.Content.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
    }

    private func actionRow(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(color)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.Colors.Stroke.divider)
            .frame(height: Self.dividerHeight)
            .padding(.horizontal, AppTheme.Spacing.md)
    }
}

#Preview {
    AccountMenuContent(onLogoutTapped: {}, onDeleteAccountTapped: {})
}
