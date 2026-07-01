# Feature: 04-icloud-setup-required

## Source

- 작업 스펙: `tasks/NO-004.md` §5.2 (iOS_iCloudSetupRequired), §2.2 (시나리오), §3.2 (iCloud 가용성 확인)
- Wireframes: `iOS_iCloudSetupRequired` — 아직 `wireframe.py`에 없음.
  spec §5.2의 구성 설명을 기준으로 구현.

## Scope

- In scope:
  - `iCloudSetupRequiredView` 신규 작성: `ICloudUnavailableReason`별 제목/본문 표시
  - "설정 앱 열기" 버튼 (`UIApplication.openSettingsURLString`, noAccount/appAccessDisabled 케이스)
  - "다시 확인" 버튼: `ICloudAvailability.isAvailable()` + `unavailableReason()` 재확인
  - "다시 확인" 성공 시 → Keychain 세션 최종 저장 → `.home` 전이
  - `SemiboldApp.swift`의 `.iCloudSetupRequired` 케이스에 연결
- Out of scope / deferred:
  - "로컬로 이용" 탈출 버튼 — spec §7 #1/#2 확정 방향: **제공하지 않음** (아래 참고)

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| iOS_iCloudSetupRequired (spec §5.2) | `iCloudSetupRequiredView.swift` | `Views/Onboarding/` 하위 |

## Decisions & Deviations

- **"로컬로 이용" 탈출 옵션 없음** — spec §7 #1 현재 방향 그대로 적용:
  iCloud 불가 상태가 지속되어도 로컬 탈출 없이 안내 화면에 머무름.
  사용자가 기기 설정을 바꾼 뒤 "다시 확인"으로 해결해야 함.
- **재실행 시 iCloud 모드 + 불가 → 임시 로컬 없음** — spec §7 #2 현재 방향 그대로 적용:
  `RootLaunchState`가 `.iCloudSetupRequired`를 반환하면 이 화면을 표시하고 진입 차단.
- **"설정 앱 열기" 노출 조건**: `noAccount` / `appAccessDisabled` 케이스에만 표시.
  `restricted` / `couldNotDetermine` / `temporarilyUnavailable` 케이스엔 표시하지 않음
  (설정 앱이 도움이 되지 않는 케이스).
- `ICloudUnavailableReason.alertTitle` / `alertMessage` 로직은 기존 코드 존재 여부 확인 후
  재사용 또는 신규 작성 (현 브랜치 상태에 따라 다를 수 있음).
- "다시 확인" 성공 흐름:
  1. `ICloudAvailability.isAvailable()` → true
  2. `KeychainSessionStore.save(AuthSession(appleUserID: <previously stored id>, mode: .icloud))`
  3. `RootLaunchState` → `.home` 전이

## Acceptance Criteria

- [ ] `iCloudSetupRequiredView` 작성: `ICloudUnavailableReason` 수신 → 케이스별 제목/본문 표시
      (spec §5.2의 5가지 케이스 모두 처리)
- [ ] "설정 앱 열기" 버튼: `noAccount` / `appAccessDisabled` 케이스에만 노출
- [ ] "다시 확인" 버튼: `ICloudAvailability.unavailableReason()` 비동기 재확인 → 성공 시 세션 저장 + `.home`
- [ ] `SemiboldApp.swift`의 `.iCloudSetupRequired` 케이스에 연결 (reason 값 전달)
- [ ] "로컬로 이용" 탈출 버튼 없음 — 안내 화면에 머무름
- [ ] `xcodegen generate && xcodebuild build` 성공

## Open Questions / Follow-ups

- spec §7 #1 / #2 방향(탈출 불허)이 최종 확정된 것으로 보고 구현.
  사용자가 이를 번복하면 이 브리프를 재구현해야 함.
