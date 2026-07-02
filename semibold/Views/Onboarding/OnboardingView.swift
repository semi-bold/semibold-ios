import SwiftUI
import AuthenticationServices

/// First-launch screen that lets the person choose between Sign in with
/// Apple (iCloud-backed) and local-only mode (NO-004 §5.1, §2.1–§2.3).
///
/// Layout matches the iOS_Onboarding wireframe (wireframe.py `ios_onboarding`):
/// LogoArea (logo mark + app name + tagline) → Apple sign-in button →
/// subtitle → "로컬로 이용" text link → footer note.
///
/// `onLaunchStateChange` is called whenever the person makes a choice that
/// should advance the root navigation — either to `.home` (local or
/// successful Apple sign-in with iCloud available) or to
/// `.iCloudSetupRequired` (Apple sign-in succeeded but iCloud is not
/// available yet). The pending Apple user ID is returned so the 04 brief's
/// iCloud-setup screen can complete the Keychain write once iCloud is fixed.
struct OnboardingView: View {
    /// Advances root navigation when the person completes a sign-in choice.
    var onLaunchStateChange: (RootLaunchState, String) -> Void

    // MARK: - View state

    /// Shown inline below the Apple sign-in button on failure/cancel.
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppTheme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.lg) {
                Spacer()

                // LogoArea: logo mark + app name + tagline
                VStack(spacing: 0) {
                    Text("Semi:bold")
                        .appTextStyle(AppTheme.Typography.title)
                        .foregroundStyle(AppTheme.Colors.text1)
                    Text("문서를 자유롭게, 안전하게")
                        .appTextStyle(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.text2)
                        .padding(.top, AppTheme.Spacing.xs)
                }

                Spacer()

                VStack(spacing: AppTheme.Spacing.md) {
                    // "Apple로 로그인" — system-provided Sign in with Apple button
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAppleSignIn(result: result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))

                    // Subtitle explaining the iCloud benefit (below the Apple button)
                    Text("로그인 시 iCloud에 데이터를 자동 저장합니다")
                        .appTextStyle(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.text2)
                        .multilineTextAlignment(.center)

                    // Inline error message (shown on failure/cancel)
                    if let message = errorMessage {
                        Text(message)
                            .appTextStyle(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.error)
                            .multilineTextAlignment(.center)
                    }

                    // "로컬로 이용" — plain text link, weaker emphasis than
                    // the Apple button (NO-004 §7 #5 decision: text link only)
                    Button {
                        handleLocalMode()
                    } label: {
                        Text("로컬로 이용")
                            .appTextStyle(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.text3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppTheme.Spacing.xl)

                Spacer()
                    .frame(height: AppTheme.Spacing.lg)

                // Footer note about local data loss risk
                Text("로컬로 이용 시 앱 삭제 시 데이터가 유실될 수 있습니다")
                    .appTextStyle(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.text3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.bottom, AppTheme.Spacing.lg)
            }
        }
    }

    // MARK: - Actions

    /// Handles the Sign in with Apple result.
    ///
    /// On success: checks iCloud availability. If available, saves the
    /// `AuthSession` with `.icloud` mode and transitions to `.home`. If not
    /// available, transitions to `.iCloudSetupRequired` with the pending
    /// Apple user ID — the 04 brief's view completes the Keychain write once
    /// the person fixes their iCloud settings.
    ///
    /// On failure/cancel: shows an inline error message and stays put.
    private func handleAppleSignIn(
        result: Result<ASAuthorization, Error>
    ) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential
                    as? ASAuthorizationAppleIDCredential
            else {
                errorMessage = "로그인 정보를 읽을 수 없어요. 다시 시도해주세요."
                return
            }
            errorMessage = nil
            let appleUserID = credential.user

            if ICloudAvailability.isAvailable() {
                // iCloud ready: persist full session and go home.
                KeychainSessionStore().save(
                    AuthSession(appleUserID: appleUserID, mode: .icloud)
                )
                onLaunchStateChange(.home, "")
            } else {
                // iCloud not yet available: hand the pending user ID to the
                // iCloud-setup screen so it can complete the Keychain write
                // after the person fixes their iCloud settings.
                onLaunchStateChange(.iCloudSetupRequired, appleUserID)
            }

        case .failure(let error):
            let nsError = error as NSError
            // ASAuthorizationError.canceled == code 1001 — don't treat
            // deliberate cancel as an error the person needs to act on.
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                errorMessage = nil
            } else {
                errorMessage = "로그인에 실패했어요. 다시 시도해주세요."
            }
        }
    }

    /// Persists a local-only session and transitions the app directly to
    /// `HomeView` — no iCloud check needed (NO-004 §2.3).
    private func handleLocalMode() {
        KeychainSessionStore().save(
            AuthSession(appleUserID: "", mode: .local)
        )
        onLaunchStateChange(.home, "")
    }
}

#Preview {
    OnboardingView { _, _ in }
}
