import SwiftUI

/// The app's settings screen, currently scoped to the "동기화" (sync)
/// section: a toggle for iCloud sync and a status banner that explains
/// what's currently happening to the person's data.
///
/// Matches the `iOS_Settings` wireframe (`wireframe.py`) and
/// `Planning_8_SyncSettingsFlow`'s callouts ①–⑤. The wireframe draws all
/// three possible banners stacked (labeled "상태 A/B/C") purely for
/// documentation — at runtime only one banner is ever shown, chosen by
/// `bannerState` below.
///
/// This view only renders the current state for now; wiring the toggle to
/// actually switch sync mode (with its confirmation alerts) and disabling
/// the toggle when iCloud is unavailable are separate steps in this same
/// brief (`.claude/features/04-settings-screen.md`).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    /// Whether this device is signed into iCloud at all (NO-002 §4.2).
    /// Re-checked on `onAppear` rather than observed live — see the
    /// brief's "상태 갱신 시점" decision.
    @State private var isICloudAvailable: Bool

    /// Local reflection of the person's sync preference, seeded from
    /// `SyncModeStore.effectiveMode()`. Toggling this doesn't yet call
    /// `DatabaseManager.switchMode` — that's wired in a later AC item.
    @State private var isSyncOn: Bool

    init(
        isICloudAvailable: Bool = ICloudAvailability.isAvailable(),
        isSyncOn: Bool = SyncModeStore().effectiveMode() == .icloud
    ) {
        self._isICloudAvailable = State(initialValue: isICloudAvailable)
        self._isSyncOn = State(initialValue: isSyncOn)
    }

    /// Which of the three status banners applies right now (`Planning_8`
    /// callouts ③④⑤): iCloud being unavailable always wins over the
    /// toggle's literal position, matching `SyncModeStore.effectiveMode`'s
    /// "iCloud 비활성 → 강제 로컬" rule.
    private var bannerState: SyncBannerState {
        guard isICloudAvailable else { return .iCloudOff }
        return isSyncOn ? .syncOn : .syncOff
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView {
                VStack(spacing: 0) {
                    sectionHeader("동기화")
                    iCloudSyncRow
                    banner(for: bannerState)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, AppTheme.Spacing.md)
                }
            }
        }
        .background(AppTheme.Colors.background)
        .toolbar(.hidden)
        .onAppear {
            isICloudAvailable = ICloudAvailability.isAvailable()
            isSyncOn = SyncModeStore().effectiveMode() == .icloud
        }
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

    // MARK: - Section header

    /// `SyncHeader` (wireframe.py:1062-1065): a surface-colored bar with
    /// an uppercase-weight label, styled like `HomeView`'s section
    /// headers for consistency.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .appTextStyle(AppTheme.Typography.label)
            .foregroundStyle(AppTheme.Colors.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 32)
            .background(AppTheme.Colors.surface)
    }

    // MARK: - Sync toggle row

    /// `Row_iCloudSync` (wireframe.py:1066-1075): label, a one-line status
    /// subtitle that mirrors the banner's headline, and the toggle
    /// itself (`Planning_8` callout ①, subtitle is callout ②).
    private var iCloudSyncRow: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("iCloud 동기화")
                        .appTextStyle(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.text1)

                    Text(bannerState.rowSubtitle)
                        .appTextStyle(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.text2)
                }

                Spacer()

                Toggle("", isOn: $isSyncOn)
                    .labelsHidden()
                    .tint(AppTheme.Colors.primary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 60)

            Rectangle()
                .fill(AppTheme.Colors.divider)
                .frame(height: 1)
                .padding(.leading, AppTheme.Spacing.md)
        }
        .background(AppTheme.Colors.background)
    }

    // MARK: - Status banner

    /// Renders exactly one of the wireframe's three `Banner_*` groups,
    /// chosen by `bannerState` — the wireframe stacks all three only to
    /// document every possible appearance at once.
    @ViewBuilder
    private func banner(for state: SyncBannerState) -> some View {
        switch state {
        case .syncOn:
            // `Banner_SyncOn` (wireframe.py:1076-1080).
            HStack(spacing: AppTheme.Spacing.md) {
                Text("☁")
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.primary)
                    .frame(width: 24, height: 24)

                Text(state.subtitle)
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.text1)

                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 48)
            .background(
                AppTheme.Colors.surface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
            )

        case .syncOff:
            // `Banner_SyncOff` (wireframe.py:1082-1087) — tap target for
            // focusing the toggle is added in a later AC item.
            HStack(spacing: AppTheme.Spacing.md) {
                Text("⚠")
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.warning)
                    .frame(width: 24, height: 24)

                Text(state.subtitle)
                    .appTextStyle(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.text1)

                Spacer()

                Text(">")
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.text2)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 64)
            .background(
                AppTheme.Colors.surface2,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
            )

        case .iCloudOff:
            // `Banner_iCloudOff` (wireframe.py:1089-1093) — red-tinted
            // background, matching the wireframe's 15%-alpha red fill.
            HStack(spacing: AppTheme.Spacing.md) {
                Text("✕")
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.error)
                    .frame(width: 24, height: 24)

                Text(state.subtitle)
                    .appTextStyle(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.error)

                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 48)
            .background(
                AppTheme.Colors.error.opacity(0.15),
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
            )
        }
    }
}

/// The three mutually-exclusive states `Planning_8_SyncSettingsFlow`
/// describes for the sync row's subtitle and banner (NO-002 §5.2):
/// syncing normally, deliberately local-only, or unable to sync at all.
private enum SyncBannerState {
    /// iCloud is available and the person has sync turned on
    /// (`Banner_SyncOn` / 상태 A).
    case syncOn
    /// iCloud is available but the person has sync turned off
    /// (`Banner_SyncOff` / 상태 B).
    case syncOff
    /// iCloud isn't available on this device at all, regardless of the
    /// person's saved preference (`Banner_iCloudOff` / 상태 C).
    case iCloudOff

    /// The (possibly multi-line) status text shown inside the banner
    /// itself (`Planning_8` callout ②, `Banner_*` groups' `lbl` layer).
    var subtitle: String {
        switch self {
        case .syncOn:
            return "iCloud에 저장 중"
        case .syncOff:
            return "이 기기에만 저장됩니다.\n앱 삭제 시 유실될 수 있어요."
        case .iCloudOff:
            return "iCloud를 사용하려면 기기 설정을 확인하세요"
        }
    }

    /// The single-line variant shown in the toggle row's subtitle
    /// (`Row_iCloudSync`'s `sub` layer is one fixed-height line in the
    /// wireframe, unlike the banner's roomier multi-line `lbl`).
    var rowSubtitle: String {
        switch self {
        case .syncOn:
            return "iCloud에 저장 중"
        case .syncOff:
            return "이 기기에만 저장됩니다"
        case .iCloudOff:
            return "iCloud를 사용하려면 기기 설정을 확인하세요"
        }
    }
}

#Preview("Sync On") {
    SettingsView(isICloudAvailable: true, isSyncOn: true)
}

#Preview("Sync Off") {
    SettingsView(isICloudAvailable: true, isSyncOn: false)
}

#Preview("iCloud Unavailable") {
    SettingsView(isICloudAvailable: false, isSyncOn: false)
}
