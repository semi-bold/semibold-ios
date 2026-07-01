# Feature: 03-onboarding-screen

## Source

- 작업 스펙: `tasks/NO-004.md` §5.1 (iOS_Onboarding), §2.1~2.3 (시나리오), §3.1 (플로우), §4.4 (자격증명 취소 감지)
- Wireframes: `iOS_Onboarding` — 아직 `wireframe.py`에 추가되지 않음.
  spec §5.1의 구성 설명을 기준으로 구현 (wireframe.py 추가는 sketch-autokit 별도 작업).
- PLANNING.md: 해당 없음

## Scope

- In scope:
  - `OnboardingView` 신규 작성 (iOS_Onboarding 스펙 §5.1 기준)
  - Sign in with Apple (`ASAuthorizationController`) 통합
  - 로그인 성공 시 iCloud 가용성 확인 → `KeychainSessionStore.save()` → 앱 상태 전이
  - "로컬로 이용" 탭 → mode=.local 저장 → HomeView 진입
  - `SemiboldApp.swift`에서 `.showOnboarding` 케이스에 `OnboardingView` 연결
  - `ICloudConsentView.swift` 제거 (OnboardingView로 대체)
  - 앱 포그라운드 진입 시 Apple 자격증명 취소(revocation) 감지 (ScenePhase.active)
- Out of scope / deferred:
  - iCloud 불가 시 안내 화면 (`iCloudSetupRequiredView`) — 04 브리프
  - 설정 앱 딥링크 — 04 브리프

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| iOS_Onboarding (spec §5.1) | `OnboardingView.swift` | `Views/Onboarding/` 하위 |

## Decisions & Deviations

- **"Apple로 로그인" 버튼**: `ASAuthorizationAppleIDButton(.signIn, style: .black)` 사용.
  시스템 제공 버튼이므로 `AppTheme` 스타일 미적용.
- **"로컬로 이용" 버튼**: 텍스트 링크 스타일 (spec §7 #5 확정 방향: 버튼보다 약한 강조).
  `AppTheme.Colors.text2` 색상의 `caption` 타이포그래피 사용.
- **로그인 성공 후 흐름**:
  1. `ICloudAvailability.isAvailable()` 1차 체크
  2. 불가이면 `ICloudAvailability.unavailableReason()` 비동기 호출
  3. 가용 → `KeychainSessionStore.save(AuthSession(appleUserID: id, mode: .icloud))`
     → `RootLaunchState` 업데이트 → `.home`
  4. 불가 → Keychain에 appleUserID만 임시 보관 후 → `.iCloudSetupRequired`
     (iCloudSetupRequiredView에서 "다시 확인" 성공 시 최종 세션 저장)
- **자격증명 취소 감지**: `SemiboldApp.body` 또는 `@Observable AppCommandCenter`에서
  `onChange(of: scenePhase)` → `.active`일 때 `ASAuthorizationAppleIDProvider.getCredentialState`
  비동기 호출. revoked/notFound → `KeychainSessionStore.delete()` → `.showOnboarding` 전이.
- 기존 `ICloudConsentView.swift` 삭제.

## Acceptance Criteria

- [ ] `OnboardingView` 작성: 앱 이름 로고, "Apple로 로그인" 버튼, "로컬로 이용" 텍스트 링크,
      부제 "로그인 시 iCloud에 데이터를 자동 저장합니다",
      하단 주석 "로컬로 이용 시 앱 삭제 시 데이터가 유실될 수 있습니다"
- [ ] "Apple로 로그인" → `ASAuthorizationController` 호출 → 성공 시 iCloud 가용성 확인 후 Keychain 저장
- [ ] "로컬로 이용" → `KeychainSessionStore.save(mode: .local)` → `RootLaunchState` `.home` 전이
- [ ] `SemiboldApp.swift`의 `.showOnboarding` 케이스에 `OnboardingView` 연결
- [ ] 로그인 실패/취소 → 에러 메시지 표시, OnboardingView 유지
- [ ] `ICloudConsentView.swift` 삭제
- [ ] 앱 포그라운드 진입 시 자격증명 revocation 감지 → `KeychainSessionStore.delete()` → `.showOnboarding`
- [ ] `xcodegen generate && xcodebuild build` 성공

## Open Questions / Follow-ups

- 없음. spec §7 #5 (로컬로 이용 강조 수준)는 텍스트 링크로 확정.
  spec §7 #4 (자격증명 취소 시 데이터 처리)도 "유지, 온보딩 복귀"로 확정.
