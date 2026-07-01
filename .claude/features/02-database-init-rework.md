# Feature: 02-database-init-rework

## Source

- 작업 스펙: `tasks/NO-004.md` §4.2 (DatabaseManager 초기화 변경), §4.3 (철수 범위)
- Wireframes: 해당 없음 (데이터/앱 레이어 전용)

## Scope

- In scope:
  - `DatabaseManager.shared` 초기화를 Keychain 세션의 `SessionMode`로부터 읽어 `syncEnabled` 결정
  - `DatabaseManager.switchMode()` 제거
  - `SyncModeStore.swift` 제거
  - `ICloudConsentChoice.swift` 제거
  - `AppCommandCenter.homeRebuildToken` / `requestHomeRebuild()` 제거
  - `SemiboldApp.swift`에서 `ICloudConsentView` 분기 제거, Keychain 세션 기반 `RootLaunchState` 재구성
  - `RootLaunchState.swift` 단순화 (Keychain 세션 유무 + mode 기반)
- Out of scope / deferred:
  - 새 `OnboardingView` UI (03 브리프)
  - 새 `iCloudSetupRequiredView` UI (04 브리프)
  - `SettingsView` / `SyncModeSwitchAction` 제거 (05 브리프)

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| — | `DatabaseManager.swift` | `shared` 초기화 변경, `switchMode()` 제거 |
| — | `RootLaunchState.swift` | Keychain 세션 기반 재구성 |
| — | `SemiboldApp.swift` | `ICloudConsentView` 분기 제거, 신규 플로우 와이어 |

## Decisions & Deviations

- `DatabaseManager.shared`는 `KeychainSessionStore.load()?.mode == .icloud`이면
  `syncEnabled: true`로 초기화. 세션 없으면 `syncEnabled: false` (앱 처음 실행 상태).
- 기존 `SyncModeStore` 대신 `KeychainSessionStore`가 모드 영속성을 담당.
  UserDefaults `sync_mode` 키는 더 이상 사용하지 않음.
- `RootLaunchState`의 새 분기:
  - Keychain 세션 없음 → `.showOnboarding` (새 케이스, OnboardingView 표시)
  - 세션 있고 mode=.local → `.home`
  - 세션 있고 mode=.icloud + iCloud 가용 → `.home`
  - 세션 있고 mode=.icloud + iCloud 불가 → `.iCloudSetupRequired` (새 케이스)
- Apple 자격증명 취소 감지는 03 브리프(OnboardingView 와이어링 시)에서 추가.
  이 브리프에서는 Keychain 기반 분기 로직만.
- `ICloudConsentChoice.apply()` 관련 테스트(`ICloudConsentChoiceTests.swift`)는
  `ICloudConsentChoice` 삭제와 함께 제거.

## Acceptance Criteria

- [ ] `DatabaseManager.shared`가 `KeychainSessionStore.load()?.mode` 기반으로 `syncEnabled` 결정
- [ ] `DatabaseManager.switchMode()` 제거
- [ ] `SyncModeStore.swift` 및 관련 테스트(`SyncModeStoreTests.swift`) 제거
- [ ] `ICloudConsentChoice.swift` 및 `ICloudConsentChoiceTests.swift` 제거
- [ ] `AppCommandCenter.homeRebuildToken` / `requestHomeRebuild()` 제거
- [ ] `SemiboldApp.swift`에서 `ICloudConsentView` 분기 제거
- [ ] `RootLaunchState.swift` 재구성: `.showOnboarding` / `.home` / `.iCloudSetupRequired` / `.databaseUnavailable`
- [ ] `xcodegen generate && xcodebuild build` 성공, 기존 통과 테스트 유지

## Open Questions / Follow-ups

- `SemiboldApp`의 `respondToConsent(sync:)` 함수 제거 후 남는 dead code 있으면
  05 브리프 cleanup 시 정리.
