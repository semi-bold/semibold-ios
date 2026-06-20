# Feature: 04-settings-screen

Status: in-progress

## Source

- Feature spec (if provided externally): none
- Wireframes / planning specs: `iOS_Settings` (wireframe.py),
  `Planning_8_SyncSettingsFlow` (planning.py)
- `tasks/<work-code>.md` section (primary): `docs/tasks/NO-002.md` §2.4,
  §3.2, §5.2, §5.3
- PLANNING.md sections (legacy fallback): none
- SERVICE.md sections: none

## Scope

- In scope:
  - `SettingsView`(가칭) 구현 — `iOS_Settings` 와이어프레임 1:1 매칭:
    NavBar, "동기화" 섹션 헤더, `iCloud 동기화` 토글 행, 상태별 배너
    3종(켜짐/꺼짐/iCloud 비활성)
  - 토글 ON/OFF에 따른 모드 전환 — 02번 브리프의 전환 함수 호출
  - 상태별 설명 텍스트 — 켜짐: "iCloud에 저장 중", 꺼짐: "이 기기에만
    저장됩니다", 불가: "iCloud를 사용하려면 기기 설정을 확인하세요"
    (NO-002 §5.2)
  - 로컬 전용 안내 배너 — 토글 꺼짐 상태일 때만 노출, 탭하면 동기화
    토글로 포커스 이동 (NO-002 §5.3)
  - 모드 전환 경고 — 로컬→iCloud: "기존 로컬 데이터를 iCloud로
    업로드합니다" 확인, iCloud→로컬: "iCloud 동기화가 중단됩니다" 확인
    (NO-002 §2.4, §3.2 flowchart)
  - iCloud 비활성 상태일 때 토글 자체를 비활성화(disabled) 처리
  - `HomeView`에서 `SettingsView`로 진입하는 경로 추가 (현재 진입점
    없음 — `navBar`의 적절한 위치에 버튼 추가)
- Out of scope / deferred:
  - 최초 실행 온보딩 팝업 → 03번 브리프 (완료됨)
  - Secret Lock, Public Space 등 다른 설정 항목 (이번 NO-002 범위는
    동기화 섹션만)

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `iOS_Settings` | `SettingsView` | 토글 + 상태 배너 3종 |
| `Planning_8_SyncSettingsFlow` | `SettingsView` 내 전환 로직 | 콜아웃 ①–⑤ 순서대로 구현 |

## Decisions & Deviations

- `HomeView`에 설정 화면 진입점이 와이어프레임/Planning 명세에 명시되어
  있지 않음 — `navBar`의 `addButton` 옆 또는 별도 아이콘으로 추가.
  정확한 위치가 모호하면 swift-reviewer 검토 시 확인
- 상태 갱신 시점: 화면이 다시 보일 때(`onAppear`)마다
  `FileManager.ubiquityIdentityToken` 재확인 — 실시간 옵저빙은 하지
  않음 (NO-002 범위에 실시간 감지 요구사항 없음). `isSyncOn`도 같은
  시점에 `SyncModeStore().effectiveMode()`로 재동기화.
- 토글 행의 상태 설명(`rowSubtitle`, 한 줄)과 배너 본문(`subtitle`, 두
  줄)을 별개 텍스트로 분리함 — NO-002 §5.2(설정 화면 항목, 한 줄
  설명)와 §5.3(로컬 전용 안내 배너, 두 줄 설명)이 서로 다른 UI
  요소를 위한 별도 문구를 명시하고 있어 그대로 따름. 와이어프레임은
  행 예시 텍스트로 ON 상태("iCloud에 저장 중")만 보여주고 있어,
  나머지 두 상태의 행 텍스트는 §5.2 명세를 직접 사용함.
- 토글 전환 결정 로직(어떤 경고를 보여줄지, iCloud 가용성 재확인)을
  `SyncModeSwitchAction`(plain enum/static 함수)으로 분리 — `View`를
  직접 구동하지 않고도 테스트 가능하도록 `ICloudConsentChoice`/
  `RootLaunchState` 패턴을 그대로 따름. `SettingsView`는 이 타입의
  결과만 받아 Alert/토글 상태를 그린다.
- 02번 브리프 `DatabaseManager.switchMode` 문서주석이 명시한 "기존
  레포지토리가 스위치 이전 컨테이너를 계속 참조하는" 문제(staleness)를
  해결하기 위해, 브리프가 제시한 옵션 1(`HomeView`를 `.id(_:)`로 강제
  재생성)을 선택함 — `AppCommandCenter`에 `homeRebuildToken` 카운터를
  추가하고, `SemiboldApp`에서 `HomeView().id(commandCenter.homeRebuildToken)`
  로 바인딩. `SettingsView`가 전환 성공 시 `commandCenter.requestHomeRebuild()`
  를 호출하면 `HomeView`의 서브트리 전체(및 `HomeViewModel`/레포지토리)가
  파괴 후 재생성되어 새 컨테이너를 즉시 반영함. 옵션 2(레포지토리가
  매번 `DatabaseManager.shared`를 live 조회하도록 바꾸는 것)는 모든
  레포지토리 호출부를 건드리는 더 큰 변경이라 보류 — `HomeView`는
  현재 앱에서 전환 시점에 이미 살아있는 유일한 화면이므로 옵션 1로
  충분히 해결됨. `AppCommandCenter`는 이미 앱 전역에서 공유되는
  `@Observable` 환경 객체라 새 의존성을 추가하지 않고도 `SettingsView`
  → `SemiboldApp` 간 신호를 보낼 수 있는 자연스러운 위치였음.
- `HomeView`로 진입하는 경로가 아직 없어(`SettingsView`로의 네비게이션
  버튼은 이 브리프의 다른 AC 항목) `SettingsView`를 단독으로 띄워
  검증하기 어려움 — `#Preview`에 `AppCommandCenter`를 주입해 빌드/
  프리뷰가 가능하도록 했고, 실제 동작 검증은 단위 테스트
  (`SyncModeSwitchActionTests`)로 결정 로직을 커버함.
- iCloud 비활성 상태의 "안내 문구"는 NO-002 §5.2가 명시한 한 줄
  설명("iCloud를 사용하려면 기기 설정을 확인하세요")을 그대로
  사용 — 이는 이전 AC(배너 3종)에서 이미 `rowSubtitle`/
  `Banner_iCloudOff`로 구현되어 있었음. 이번 AC에서는 토글
  자체에 `.disabled(!isICloudAvailable)`만 추가함. 와이어프레임/
  `tasks/NO-002.md`(§2.4, §3.2, §5.2, §5.3, §6) 어디에도 비활성
  토글 행 전용의 *별도* 안내 문구가 명시되어 있지 않아, 기존
  한 줄 설명 + 토글 비활성화 조합으로 충분하다고 판단함.
- 토글이 비활성화되면 사람이 탭으로 `requestSwitch`의
  `.iCloudUnavailable` 분기(`isICloudUnavailableGuidancePresented`
  얼럿)에 도달할 입구가 사실상 막힘 — 그러나 이 분기를 죽은 코드로
  보고 제거하지 않음. `SyncModeSwitchAction.prompt`는 `isSyncOn`이
  프로그래밍적으로 변경되는 경로(예: 화면이 떠 있는 동안 iCloud
  가용성이 바뀌는 드문 레이스)에 대한 방어 로직으로 유지하고,
  `SyncModeSwitchActionTests`로 계속 커버함.

## Acceptance Criteria

- [x] `SettingsView`가 `iOS_Settings` 와이어프레임과 1:1 매칭됨 (토글
      행, 상태 배너 3종 중 현재 상태에 맞는 배너만 노출)
- [x] 토글 ON↔OFF 전환 시 02번 브리프의 전환 함수가 호출되고, 전환 전
      확인 Alert(로컬→iCloud / iCloud→로컬 각각 다른 문구)가 표시됨
- [x] iCloud 비활성 상태에서는 토글이 비활성화(disabled)되고 안내
      문구가 표시됨
- [ ] 로컬 전용 안내 배너가 토글 OFF일 때만 노출되고 탭하면 토글
      위치로 스크롤/포커스됨
- [ ] `HomeView`에서 `SettingsView`로 진입할 수 있는 버튼이 추가됨

## Open Questions / Follow-ups

- 없음
