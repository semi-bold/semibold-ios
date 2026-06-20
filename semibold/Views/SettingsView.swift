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
/// Flipping the toggle never applies the new mode immediately — it shows
/// NO-002 §2.4's confirmation warning for that direction first
/// (`SyncModeSwitchAction.prompt`), and only calls
/// `DatabaseManager.switchMode` (via `SyncModeSwitchAction.confirmSwitch`)
/// once the person confirms. Canceling, or a failed switch, reverts the
/// toggle to its pre-tap position (NO-002 §3.2 "토글 원복").
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    /// Lets a successful switch request `HomeView`'s subtree be rebuilt
    /// against the newly-active container — see
    /// `AppCommandCenter.homeRebuildToken`'s doc comment for why that's
    /// necessary instead of just calling `switchMode` in isolation.
    @Environment(AppCommandCenter.self) private var commandCenter

    /// Whether this device is signed into iCloud at all (NO-002 §4.2).
    /// Re-checked on `onAppear` rather than observed live — see the
    /// brief's "상태 갱신 시점" decision.
    @State private var isICloudAvailable: Bool

    /// Local reflection of the person's sync preference, seeded from
    /// `SyncModeStore.effectiveMode()`.
    @State private var isSyncOn: Bool

    /// The last value `isSyncOn` held *before* the change currently being
    /// confirmed — what it reverts to on "취소" or on a failed switch
    /// (NO-002 §3.2 "토글 원복").
    @State private var isSyncOnBeforePendingChange: Bool

    /// The confirmation warning currently being shown for a toggle change
    /// in progress, or `nil` when no toggle change is pending. Drives the
    /// confirm/cancel `Alert` below.
    @State private var pendingPrompt: SyncModeSwitchPrompt?

    /// Whether to show NO-002 §3.2's "iCloud 설정 필요" guidance — shown
    /// instead of a confirm/cancel warning when 로컬 → iCloud is attempted
    /// while iCloud isn't actually available right now.
    @State private var isICloudUnavailableGuidancePresented = false

    /// Whether to show NO-002 §7's "동기화 설정을 변경하지 못했습니다"
    /// failure alert, after a confirmed switch's `DatabaseManager.switchMode`
    /// call throws.
    @State private var isSwitchFailureAlertPresented = false

    /// Set right before `revertToggle()` programmatically reassigns
    /// `isSyncOn`, so the `.onChange(of: isSyncOn)` that reassignment
    /// triggers can tell it's a revert rather than a new person-initiated
    /// toggle and skip showing another prompt for it.
    @State private var isRevertingToggle = false

    init(
        isICloudAvailable: Bool = ICloudAvailability.isAvailable(),
        isSyncOn: Bool = SyncModeStore().effectiveMode() == .icloud
    ) {
        self._isICloudAvailable = State(initialValue: isICloudAvailable)
        self._isSyncOn = State(initialValue: isSyncOn)
        self._isSyncOnBeforePendingChange = State(initialValue: isSyncOn)
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
            isSyncOnBeforePendingChange = isSyncOn
        }
        .onChange(of: isSyncOn) { _, newValue in
            if isRevertingToggle {
                isRevertingToggle = false
                return
            }
            requestSwitch(to: newValue ? .icloud : .local)
        }
        .alert(
            alertTitle(for: pendingPrompt),
            isPresented: isPendingPromptAlertPresented,
            presenting: pendingPrompt
        ) { prompt in
            Button("취소", role: .cancel) {
                revertToggle()
            }
            Button("확인") {
                confirmSwitch(for: prompt)
            }
        } message: { prompt in
            if let warningMessage = prompt.warningMessage {
                Text(warningMessage)
            }
        }
        .alert("iCloud 설정 필요", isPresented: $isICloudUnavailableGuidancePresented) {
            Button("확인") {
                revertToggle()
            }
        } message: {
            Text("iCloud를 사용하려면 기기 설정을 확인하세요.")
        }
        .alert("동기화 설정을 변경하지 못했습니다", isPresented: $isSwitchFailureAlertPresented) {
            Button("확인") {
                revertToggle()
            }
        }
    }

    // MARK: - Sync mode switching

    /// Reacts to the toggle's new (not-yet-committed) position by asking
    /// `SyncModeSwitchAction` what to show, per NO-002 §3.2's "변경
    /// 방향?" branch — never applies `newMode` directly.
    private func requestSwitch(to newMode: SyncMode) {
        switch SyncModeSwitchAction.prompt(for: newMode) {
        case .confirmLocalToICloud:
            pendingPrompt = .confirmLocalToICloud
        case .confirmICloudToLocal:
            pendingPrompt = .confirmICloudToLocal
        case .iCloudUnavailable:
            isICloudUnavailableGuidancePresented = true
        }
    }

    /// "확인": actually performs the switch this prompt was shown for, and
    /// either commits the toggle's new position or reverts it
    /// (NO-002 §3.2/§7).
    private func confirmSwitch(for prompt: SyncModeSwitchPrompt) {
        let newMode: SyncMode = prompt == .confirmLocalToICloud ? .icloud : .local

        let succeeded = SyncModeSwitchAction.confirmSwitch(
            to: newMode,
            databaseManager: DatabaseManager.shared,
            storeURL: DatabaseManager.defaultStoreURL()
        )

        guard succeeded else {
            isSwitchFailureAlertPresented = true
            return
        }

        // Commit: the toggle's current position already reflects
        // `newMode`, so just record it as the new "before" baseline and
        // rebuild `HomeView`'s subtree so its repositories pick up the
        // container `switchMode` just swapped in (see
        // `AppCommandCenter.homeRebuildToken`'s doc comment).
        isSyncOnBeforePendingChange = isSyncOn
        commandCenter.requestHomeRebuild()
    }

    /// "취소", or a failed switch: puts the toggle back where it was
    /// before this change began (NO-002 §3.2 "토글 원복").
    private func revertToggle() {
        guard isSyncOn != isSyncOnBeforePendingChange else { return }
        isRevertingToggle = true
        isSyncOn = isSyncOnBeforePendingChange
    }

    private var isPendingPromptAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingPrompt != nil },
            set: { isPresented in
                if !isPresented {
                    pendingPrompt = nil
                }
            }
        )
    }

    /// `pendingPrompt` (and therefore this function) only ever holds
    /// `.confirmLocalToICloud`/`.confirmICloudToLocal` — `requestSwitch`
    /// routes `.iCloudUnavailable` straight to its own separate guidance
    /// alert below instead of setting `pendingPrompt`. The remaining
    /// cases exist only so this switch stays exhaustive.
    private func alertTitle(for prompt: SyncModeSwitchPrompt?) -> String {
        switch prompt {
        case .confirmLocalToICloud:
            return "iCloud 동기화로 전환"
        case .confirmICloudToLocal:
            return "로컬 전용으로 전환"
        case .iCloudUnavailable, .none:
            return ""
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
        .environment(AppCommandCenter())
}

#Preview("Sync Off") {
    SettingsView(isICloudAvailable: true, isSyncOn: false)
        .environment(AppCommandCenter())
}

#Preview("iCloud Unavailable") {
    SettingsView(isICloudAvailable: false, isSyncOn: false)
        .environment(AppCommandCenter())
}
