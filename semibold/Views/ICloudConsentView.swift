import SwiftUI

/// First-launch prompt asking whether to sync documents through iCloud
/// (NO-002 §3.1/§5.1, `iOS_ICloudConsent` wireframe;
/// `Planning_7_ICloudConsentFlow` callouts ①–⑤).
///
/// Presented full-screen from `SemiboldApp` over `HomeView` as a dim
/// overlay with a centered modal card, matching `ios_icloud_consent` in
/// `wireframe.py`. The two buttons' `sync_mode` + container-switching
/// behavior (callouts ③④) is wired by the caller through `onUseSync`/
/// `onUseLocalOnly` — see `SemiboldApp.respondToConsent` and
/// `ICloudConsentChoice.apply`.
struct ICloudConsentView: View {
    /// Called when the person taps "동기화 사용" (callout ③). The caller
    /// is expected to persist `sync_mode = "icloud"`, switch to the
    /// iCloud container, and dismiss this view.
    var onUseSync: () -> Void = {}

    /// Called when the person taps "나중에" (callout ④). The caller is
    /// expected to persist `sync_mode = "local"`, switch to the local
    /// container, and dismiss this view.
    var onUseLocalOnly: () -> Void = {}

    var body: some View {
        ZStack {
            // `DimOverlay` (wireframe.py:1024) — semi-transparent black
            // covering the full screen behind the modal card.
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            consentCard
        }
    }

    /// `ConsentModal` (wireframe.py:1025-1044) — the centered card itself.
    private var consentCard: some View {
        VStack(spacing: 0) {
            // ① iCloud icon + title (callout ①) — lets the person see at
            // a glance what the popup is asking before they read the body.
            iconBadge
                .padding(.top, AppTheme.Spacing.lg)

            Text("iCloud로 동기화할까요?")
                .appTextStyle(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.text1)
                .multilineTextAlignment(.center)
                .padding(.top, AppTheme.Spacing.md)

            // ② Body copy (callout ②) — explains the benefit of syncing
            // (survives app deletion, available on every device) so the
            // person knows why they'd want to opt in.
            Text("문서를 iCloud에 저장하면 앱을\n삭제해도 데이터가 유지되고,\niPhone과 Mac에서 함께 볼 수 있어요.")
                .appTextStyle(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.text2)
                .multilineTextAlignment(.center)
                .padding(.top, AppTheme.Spacing.md)
                .padding(.horizontal, AppTheme.Spacing.md)

            // ③ Primary action — "동기화 사용".
            Button(action: onUseSync) {
                Text("동기화 사용")
                    .appTextStyle(AppTheme.Typography.button)
                    .foregroundStyle(AppTheme.Colors.text1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        AppTheme.Colors.primary,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    )
            }
            .padding(.top, AppTheme.Spacing.lg)
            .padding(.horizontal, AppTheme.Spacing.md)

            Divider()
                .overlay(AppTheme.Colors.divider)
                .padding(.top, AppTheme.Spacing.md)
                .padding(.horizontal, AppTheme.Spacing.md)

            // ④ Secondary action — "나중에" (text-only, no fill).
            Button(action: onUseLocalOnly) {
                Text("나중에")
                    .appTextStyle(AppTheme.Typography.button)
                    .foregroundStyle(AppTheme.Colors.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .padding(.horizontal, AppTheme.Spacing.md)

            // ⑤ Reassurance that this choice isn't permanent (footer note).
            Text("나중에 설정에서 바꿀 수 있습니다.")
                .appTextStyle(AppTheme.Typography.label)
                .foregroundStyle(AppTheme.Colors.text3)
                .multilineTextAlignment(.center)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.lg)
                .padding(.horizontal, AppTheme.Spacing.md)
        }
        .frame(width: 320)
        .background(
            AppTheme.Colors.surface,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
        )
    }

    /// `IconArea` (wireframe.py:1027-1030) — a ☁ glyph in a tinted
    /// rounded badge above the title.
    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .fill(AppTheme.Colors.primary.opacity(0.18))
                .frame(width: 48, height: 48)

            Text("☁")
                .appTextStyle(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.primary)
        }
    }
}

#Preview {
    ICloudConsentView()
}
