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

- 팝업 표시 위치: `SemiboldApp`의 루트 `switch launchState`에서
  `.showICloudConsent`일 때는 `ICloudConsentView`만 그리고
  `HomeView`는 아예 생성하지 않음 — `ICloudConsentView`가 자체적으로
  전체 화면 dim overlay를 그리므로 별도의 배경 없이도 화면을 단독으로
  채울 수 있음. `.home`으로 전환된 뒤에야 `HomeView`가 생성됨 (아래
  스테일 컨테이너 항목 참고).
- "나중에 설정에서 바꿀 수 있습니다" 문구(와이어프레임 note 레이어)는
  그대로 텍스트로 구현 — 별도 동작은 없음 (정보 제공용)
- `ICloudConsentView` 색상/타이포그래피는 와이어프레임의 리터럴 hex/pt
  값이 아니라 **가장 가까운 기존 `AppTheme` 토큰**에 매핑함 (예:
  와이어프레임 `#0a84ff`/18pt → `AppTheme.Colors.primary`/`Typography.title`
  20pt). 차이가 시각적으로 무시할 수준이라 화면 전용 토큰을 새로
  추가하지 않음 — `AppTheme` 중앙화 원칙(CLAUDE.md §3) 우선.
- 버튼 동작은 `ICloudConsentChoice.apply(sync:databaseManager:storeURL:
  syncModeStore:)`로 분리 — `SemiboldApp`이 `ICloudConsentView`의
  `onUseSync`/`onUseLocalOnly` 클로저에서 이를 호출하고, 성공/실패와
  무관하게 곧바로 `launchState = .home`으로 전환해 팝업을 닫음. 이
  단계는 `HomeView` 진입 전이라 보여줄 설정 화면이 없고, 첫 실행
  팝업에 "재시도" UI를 두는 것도 부적절하다고 판단해 사용자를 막지
  않는 쪽을 선택함.
- "동기화 사용" 전환이 실패하는 경우(엔타이틀먼트 미설정 등으로 실제
  CloudKit에 닿지 못하는 현 시점 포함) `DatabaseManager.switchMode`는
  이미 원래 활성 컨테이너로 롤백한 상태이므로, `ICloudConsentChoice`는
  `sync_mode`를 `"icloud"`로 남기지 않고 명시적으로 `.local`로
  저장함 — 실패한 상태를 그대로 두면 실제로는 로컬 컨테이너로
  동작하면서 `sync_mode`만 `"icloud"`라고 거짓 표시하는 불일치가
  생기기 때문. 이 분기는 NO-002 §7의 "모드 전환 실패: 원래 모드로
  롤백, 알림 표시"와는 다른 상황(설정 화면 재전환이 아니라 온보딩
  최초 선택)이라 알림 표시는 04번 브리프(설정 화면)의 책임으로 남기고
  여기서는 침묵 처리함.
- `DatabaseManager.switchMode`의 "기존에 생성된 리포지토리는 전환 전
  컨테이너를 계속 참조한다" 경고를 실제로 피하기 위해 `HomeView`는
  `launchState == .home`일 때만 생성됨 — `.showICloudConsent` 상태에서는
  `ICloudConsentView`만 그려지고 `HomeView()`는 뷰 트리에 전혀 존재하지
  않으므로, `HomeViewModel`과 그 안의 `FolderRepository`/
  `DocumentRepository`도 함께 생성되지 않는다. `launchState`가 `.home`으로
  바뀌는 시점은 항상 `ICloudConsentChoice.apply`(실행됐다면)가 이미 끝난
  뒤이므로, `HomeViewModel`의 리포지토리는 전환 전(stale) 컨테이너의
  컨텍스트를 capture할 수 없음 — 생성 자체가 전환 이후로 지연되기
  때문.

## Acceptance Criteria

- [x] 앱 최초 실행 시(`sync_mode` 미설정) iCloud 가용 상태면
      `ICloudConsentView`가 표시되고, 불가능 상태면 팝업 없이 로컬
      전용으로 바로 `HomeView` 진입함 (NO-002 §3.1 flowchart)
- [x] `ICloudConsentView`가 `iOS_ICloudConsent` 와이어프레임과 1:1
      매칭됨 (아이콘, 제목, 본문, 버튼 2개, dim overlay, radius/색상
      토큰은 `AppTheme` 사용)
- [x] "동기화 사용" 탭 시 `sync_mode = "icloud"` 저장 + iCloud 컨테이너로
      초기화, "나중에" 탭 시 `sync_mode = "local"` 저장 + 로컬 컨테이너로
      초기화됨
- [ ] 한 번 응답한 이후에는 앱을 재실행해도 팝업이 다시 표시되지 않음

## Open Questions / Follow-ups

- 없음
