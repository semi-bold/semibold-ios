import SwiftUI

/// Shown when the person has signed in with Apple but iCloud is not
/// available on this device (NO-004 §2.2, §5.2).
///
/// Layout matches the `iOS_iCloudSetupRequired` wireframe artboard:
/// - StatusBar tint at the top edge
/// - Orange-tinted cloud warning icon (WarningIcon group, y≈160)
/// - Reason-specific title (y≈256) and body message (y≈304)
/// - ReasonBadge pill showing the current unavailability case label (y≈368)
/// - "설정 앱 열기" filled primary button (`.noAccount` / `.appAccessDisabled` only, y≈420)
/// - "다시 확인" surface-3 button, always shown (y≈484)
///
/// There is no "로컬로 이용" escape — per spec §1.3 and the brief's
/// Decisions, the person must fix their iCloud settings to proceed.
struct ICloudSetupRequiredView: View {
    /// The reason iCloud was not available when the person landed here.
    /// Updated in-place if "다시 확인" is tapped and iCloud is still not
    /// available, so the guidance message stays accurate.
    @State private var reason: ICloudUnavailableReason

    /// The Apple user ID returned by Sign in with Apple (stored as
    /// "pending" until iCloud is confirmed available). Used to complete
    /// the Keychain write when "다시 확인" succeeds.
    let pendingAppleUserID: String

    /// Called when iCloud becomes available after a "다시 확인" tap — the
    /// parent should transition to `HomeView` after this fires.
    let onSuccess: () -> Void

    /// Whether the async "다시 확인" check is in flight.
    @State private var isChecking: Bool = false

    init(
        reason: ICloudUnavailableReason,
        pendingAppleUserID: String,
        onSuccess: @escaping () -> Void
    ) {
        _reason = State(initialValue: reason)
        self.pendingAppleUserID = pendingAppleUserID
        self.onSuccess = onSuccess
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppTheme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // StatusBar — 44pt tint strip matching the wireframe `StatusBar`
                // rect. Uses `AppTheme.Colors.surface` (#1C1C1E), the established
                // convention for StatusBar/NavBar backgrounds across the app.
                AppTheme.Colors.surface
                    .frame(height: 44)
                    .ignoresSafeArea(edges: .top)

                // Gap from StatusBar bottom (44) to WarningIcon top (160)
                Spacer().frame(height: 116)

                // WarningIcon — 72×72 group: orange-tinted rounded rect bg +
                // cloud glyph centred inside (wireframe WarningIcon, y=160).
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(AppTheme.Colors.warning.opacity(0.18))
                        .frame(width: 72, height: 72)

                    Text("☁")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.warning)
                        // wireframe places the icon text at y=12 inside the
                        // 72pt group, so it sits slightly above centre.
                        .offset(y: -4)
                }
                .frame(width: 72, height: 72)

                // Gap from WarningIcon bottom (232) to title top (256)
                Spacer().frame(height: 24)

                // Title — 22pt bold white, centred (wireframe title, y=256)
                Text(reason.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.text1)
                    .multilineTextAlignment(.center)
                    .frame(height: 32)
                    .padding(.horizontal, 24)

                // Gap from title bottom (288) to body top (304)
                Spacer().frame(height: 16)

                // Body — 15pt regular, muted grey, centred (wireframe body, y=304)
                Text(reason.message)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.Colors.text2)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 52)
                    .padding(.horizontal, 24)

                // Gap from body bottom (356) to ReasonBadge top (368)
                Spacer().frame(height: 12)

                // ReasonBadge — 160×28 pill: orange-tinted bg + case-name label
                // (wireframe ReasonBadge group, y=368).
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.Colors.warning.opacity(0.18))
                        .frame(width: 160, height: 28)

                    Text(reason.badgeLabel)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppTheme.Colors.warning)
                }
                .frame(width: 160, height: 28)

                // Gap from ReasonBadge bottom (396) to Btn_OpenSettings top (420)
                Spacer().frame(height: 24)

                // "설정 앱 열기" — filled primary button, shown only for the two
                // cases where the Settings app can directly help the person.
                // Wireframe Btn_OpenSettings: solid #0a84ff bg (≈ AppTheme primary),
                // white bold label, 52pt tall, 12pt radius (y=420).
                if reason.canOpenSettings {
                    Button {
                        openSettings()
                    } label: {
                        Text("설정 앱 열기")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.text1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                                    .fill(AppTheme.Colors.primary)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 32)

                    // Gap between the two buttons (wireframe: 484 − 472 = 12pt)
                    Spacer().frame(height: 12)
                }

                // "다시 확인" — always shown; surface-3 background with white
                // label. Wireframe Btn_Retry: #3a3a3c bg, 52pt tall, 12pt radius
                // (y=484 when settings button is visible, y=420 otherwise).
                Button {
                    Task { await retryCheck() }
                } label: {
                    Group {
                        if isChecking {
                            ProgressView()
                                .tint(AppTheme.Colors.text1)
                        } else {
                            Text("다시 확인")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(AppTheme.Colors.text1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                            .fill(AppTheme.Colors.surface3)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isChecking)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Re-checks iCloud availability. On success, saves the full Keychain
    /// session and calls `onSuccess()`. On continued failure, updates
    /// `reason` so the message reflects the current state.
    private func retryCheck() async {
        isChecking = true
        defer { isChecking = false }

        let newReason = await ICloudAvailability.unavailableReason()
        if newReason == nil {
            // iCloud is now available — complete the session write and go home.
            KeychainSessionStore().save(
                AuthSession(appleUserID: pendingAppleUserID, mode: .icloud)
            )
            onSuccess()
        } else {
            // Still not available — show the updated reason.
            reason = newReason!
        }
    }
}

// MARK: - Per-reason copy

private extension ICloudUnavailableReason {
    /// The headline shown at the top of the guidance screen (spec §5.2).
    var title: String {
        switch self {
        case .noAccount:
            return "iCloud 로그인이 필요해요"
        case .appAccessDisabled:
            return "iCloud 접근 권한이 꺼져 있어요"
        case .restricted:
            return "iCloud 사용이 제한되어 있어요"
        case .couldNotDetermine:
            return "iCloud 상태를 확인할 수 없어요"
        case .temporarilyUnavailable:
            return "iCloud를 잠시 사용할 수 없어요"
        }
    }

    /// The explanatory body text (spec §5.2).
    var message: String {
        switch self {
        case .noAccount:
            return "이 기기에 로그인된 iCloud 계정이 없어요. 설정 앱에서 iCloud에 로그인해주세요."
        case .appAccessDisabled:
            return "iCloud 계정은 로그인되어 있지만, 이 앱의 iCloud 접근 권한이 꺼져 있어요. 설정 앱의 iCloud 항목에서 권한을 켜주세요."
        case .restricted:
            return "스크린타임 등 기기 정책으로 iCloud 사용이 제한된 상태예요."
        case .couldNotDetermine:
            return "네트워크 연결을 확인한 뒤 다시 시도해주세요."
        case .temporarilyUnavailable:
            return "잠시 후 다시 시도해주세요."
        }
    }

    /// The short case label shown in the ReasonBadge pill
    /// (wireframe `ReasonBadge.lbl`).
    var badgeLabel: String {
        switch self {
        case .noAccount:
            return "noAccount"
        case .appAccessDisabled:
            return "appAccessDisabled"
        case .restricted:
            return "restricted"
        case .couldNotDetermine:
            return "couldNotDetermine"
        case .temporarilyUnavailable:
            return "temporarilyUnavailable"
        }
    }

    /// `true` for the two cases where opening the Settings app directly
    /// helps the person fix the issue (spec §5.2 버튼 노출 조건).
    var canOpenSettings: Bool {
        switch self {
        case .noAccount, .appAccessDisabled:
            return true
        case .restricted, .couldNotDetermine, .temporarilyUnavailable:
            return false
        }
    }
}

#Preview {
    ICloudSetupRequiredView(
        reason: .noAccount,
        pendingAppleUserID: "preview-user-id"
    ) {}
}
