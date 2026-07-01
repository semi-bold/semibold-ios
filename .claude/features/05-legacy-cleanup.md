# Feature: 05-legacy-cleanup

## Source

- 작업 스펙: `tasks/NO-004.md` §4.3 (철수 범위), §5.3 (기존 화면 변경)
- Wireframes: 해당 없음 (코드 제거 작업)

## Scope

- In scope:
  - `SettingsView.swift` 및 `Views/Settings/` 디렉토리 삭제
  - `SyncModeSwitchAction.swift` 삭제 (및 관련 테스트 `SyncModeSwitchActionTests.swift` 정리)
  - `SyncModeSwitchPrompt` 관련 코드 잔여물 정리
  - `ToastView.swift` 삭제
  - `HomeView.swift`에서 Settings 시트 진입점 (gear icon, `isSettingsSheetPresented`) 제거
  - `HomeView.swift`에서 NO-002에서 남은 동기화 관련 `@State` 잔여물 정리
  - `SemiboldApp.swift` 잔여 NO-002 주석/dead code 정리
  - 빌드 성공 + 전체 테스트 통과 확인
- Out of scope / deferred:
  - 새 기능 추가 없음 — 제거만

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| — | `HomeView.swift` | gear icon + isSettingsSheetPresented 제거 |

## Decisions & Deviations

- 이 브리프의 시작 시점에 이미 01~04 브리프가 구현 완료된 상태.
  `SettingsView.swift`와 `SyncModeSwitchAction.swift` 등은 01~04 구현 후에는
  더 이상 참조되지 않아야 하므로 삭제해도 컴파일 에러 없어야 함.
- `SyncModeSwitchActionTests.swift`는 `SyncModeSwitchAction` 자체가 삭제되므로
  같이 제거. `ICloudAvailabilityTests.swift`는 `ICloudAvailability`가 유지되므로 유지.
- `HomeView`의 gear icon (`settingsButton`, `isSettingsSheetPresented`)은
  이전 브리프에서 미처 제거되지 않았다면 이 브리프에서 제거.
  이미 없다면 이 항목은 no-op.

## Acceptance Criteria

- [ ] `SettingsView.swift` 및 `Views/Settings/` 삭제
- [ ] `SyncModeSwitchAction.swift` 삭제
- [ ] `SyncModeSwitchActionTests.swift` 삭제
- [ ] `ToastView.swift` 삭제
- [ ] `HomeView.swift` gear icon / `isSettingsSheetPresented` / Settings 시트 제거 (존재하는 경우)
- [ ] `HomeView.swift` NO-002 잔여 동기화 `@State` 정리 (존재하는 경우)
- [ ] `xcodegen generate && xcodebuild build` 성공
- [ ] `xcodebuild test` — 현존 통과 테스트 전부 통과

## Open Questions / Follow-ups

- 이 시점에 남아있는 NO-002 코드를 발견하면 이 브리프에서 함께 제거.
