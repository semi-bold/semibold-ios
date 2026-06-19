# Feature: 04-settings-screen

Status: draft

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
  않음 (NO-002 범위에 실시간 감지 요구사항 없음)

## Acceptance Criteria

- [ ] `SettingsView`가 `iOS_Settings` 와이어프레임과 1:1 매칭됨 (토글
      행, 상태 배너 3종 중 현재 상태에 맞는 배너만 노출)
- [ ] 토글 ON↔OFF 전환 시 02번 브리프의 전환 함수가 호출되고, 전환 전
      확인 Alert(로컬→iCloud / iCloud→로컬 각각 다른 문구)가 표시됨
- [ ] iCloud 비활성 상태에서는 토글이 비활성화(disabled)되고 안내
      문구가 표시됨
- [ ] 로컬 전용 안내 배너가 토글 OFF일 때만 노출되고 탭하면 토글
      위치로 스크롤/포커스됨
- [ ] `HomeView`에서 `SettingsView`로 진입할 수 있는 버튼이 추가됨

## Open Questions / Follow-ups

- 없음
