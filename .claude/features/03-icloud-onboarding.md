# Feature: 03-icloud-onboarding

Status: in-progress

## Source

- Feature spec (if provided externally): none
- Wireframes / planning specs: `iOS_ICloudConsent` (wireframe.py),
  `Planning_7_ICloudConsentFlow` (planning.py)
- `tasks/<work-code>.md` section (primary): `docs/tasks/NO-002.md` §2.1,
  §3.1, §5.1
- PLANNING.md sections (legacy fallback): none
- SERVICE.md sections: none

## Scope

- In scope:
  - 최초 실행 감지 로직 — `sync_mode`가 미설정(`nil`)인 경우를 "최초
    실행"으로 판단 (02번 브리프의 `SyncModeStore` 사용)
  - iCloud 가용성에 따른 분기: 가능하면 동의 팝업 표시, 불가능하면
    팝업 없이 로컬 전용 자동 시작 (NO-002 §2.3, §3.1 flowchart)
  - `ICloudConsentView`(가칭) 구현 — `iOS_ICloudConsent` 와이어프레임
    1:1 매칭: ☁ 아이콘, 제목, 본문, "동기화 사용"/"나중에" 버튼, dim
    overlay 모달
  - 동의 결과에 따른 컨테이너 초기화 분기 — "동기화 사용" → `sync_mode
    = "icloud"` + `NSPersistentCloudKitContainer` 초기화, "나중에" →
    `sync_mode = "local"` + `NSPersistentContainer` 초기화 (02번
    브리프의 분기 함수 호출)
  - 팝업은 1회만 표시 — 거부 후 재실행 시 다시 표시되지 않음
- Out of scope / deferred:
  - 설정 화면에서의 모드 재전환 UI → 04번 브리프
  - iCloud 비활성 상태 안내 문구의 상세 UX → 04번 브리프 (이 브리프는
    팝업 자체를 건너뛰고 로컬 전용으로 진입시키는 것까지만)

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `iOS_ICloudConsent` | `ICloudConsentView` | dim overlay + 중앙 모달 카드 |
| `Planning_7_ICloudConsentFlow` | `SemiboldApp`의 최초 실행 분기 | 콜아웃 ①–⑤ 순서대로 구현 |

## Decisions & Deviations

- 팝업 표시 위치: `SemiboldApp`의 루트 뷰 분기에서 `.fullScreenCover`
  또는 `.overlay`로 `HomeView` 위에 표시 (NavigationStack 진입 전에
  분기 결정이 끝나야 하므로, `HomeView`가 그려지기 전 단계에서 처리)
- "나중에 설정에서 바꿀 수 있습니다" 문구(와이어프레임 note 레이어)는
  그대로 텍스트로 구현 — 별도 동작은 없음 (정보 제공용)

## Acceptance Criteria

- [x] 앱 최초 실행 시(`sync_mode` 미설정) iCloud 가용 상태면
      `ICloudConsentView`가 표시되고, 불가능 상태면 팝업 없이 로컬
      전용으로 바로 `HomeView` 진입함 (NO-002 §3.1 flowchart)
- [ ] `ICloudConsentView`가 `iOS_ICloudConsent` 와이어프레임과 1:1
      매칭됨 (아이콘, 제목, 본문, 버튼 2개, dim overlay, radius/색상
      토큰은 `AppTheme` 사용)
- [ ] "동기화 사용" 탭 시 `sync_mode = "icloud"` 저장 + iCloud 컨테이너로
      초기화, "나중에" 탭 시 `sync_mode = "local"` 저장 + 로컬 컨테이너로
      초기화됨
- [ ] 한 번 응답한 이후에는 앱을 재실행해도 팝업이 다시 표시되지 않음

## Open Questions / Follow-ups

- 없음
