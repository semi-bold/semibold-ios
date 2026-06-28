# Feature: 02-swipe-actions

## Source

- Feature spec (if provided externally): none
- Wireframes / planning specs: `iOS_HomeViewSwipe` (`ios_homeviewswipe`,
  wireframe.py), `iOS_SwipeAction` (`ios_swipeaction`, wireframe.py),
  `Planning_9_SwipeActionFlow` (planning.py — note: NO-003 §3.2 calls
  this "Planning_8" but the actual artifact in planning.py is numbered
  `Planning_9_SwipeActionFlow`; Planning_7/8 were already taken by
  `Planning_7_ICloudConsentFlow`/`Planning_8_SyncSettingsFlow` from
  NO-002 — use the real name `Planning_9_SwipeActionFlow`)
- `tasks/<work-code>.md` section (primary): `docs/tasks/NO-003.md`
  §1.3, §2.2, §3.2
- PLANNING.md sections (legacy fallback): §6.1 (폴더 삭제 정책,
  soft delete), §6.2 (문서 요구사항), §19 (Secret Lock 확장점 — 블록
  잠금의 근거)
- SERVICE.md sections: none

## Scope

- In scope:
  - `HomeView`/`FolderContentsView`의 폴더·문서 행에 좌로 스와이프 시
    "편집"(파란색, 80px)/"삭제"(빨간색, 80px) 액션 노출 — iOS 표준
    List swipe action 사용
  - "편집" 액션 — 폴더는 이름 수정, 문서는 제목 수정 (인라인 또는 이름
    변경 시트, 기존 `NewFolderSheet`/`NewDocumentSheet`의 이름 입력
    패턴 재사용 가능)
  - "삭제" 액션 — 확인 알림 후 soft delete (`FolderRepository`/
    `DocumentRepository`의 기존 `softDelete(id:)` 호출). 하위 폴더/문서가
    있는 폴더 삭제 시 포함 여부를 묻는 확인 다이얼로그 표시
  - `DetailView`의 블록에 동일한 좌로 스와이프 제스처로 "잠금" 액션
    노출 — 이번 범위는 **UI 표시만** (탭 시 실제 동작은 없음 또는
    "아직 지원하지 않음" 정도의 최소 피드백), 실제 암호화/Secret Lock
    기능은 제외 (NO-001 §1.2, PLANNING §19)
- Out of scope / deferred:
  - Secret Lock 실제 암호화 동작 (NO-001 §1.2에서 이미 제외 확정)
  - 폴더/문서 hard delete UI (휴지통 비우기 등) — soft delete까지만
  - 스와이프 액션의 정렬/드래그 재배치 — 이번 범위는 편집/삭제/잠금만

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `iOS_HomeViewSwipe` | `HomeView`/`FolderContentsView` 행 스와이프 | 편집/삭제 버튼 |
| `iOS_SwipeAction` | `DetailView` 블록 스와이프 | 잠금 버튼 (UI만) |
| `Planning_9_SwipeActionFlow` | 위 두 화면의 스와이프 로직 | 콜아웃 ①–⑤ 순서대로 구현 |

## Decisions & Deviations

- 스와이프 액션 구성은 NO-003 §1.3에서 이미 결정됨 — 편집(파란색
  80px) + 삭제(빨간색 80px), 에디터 블록 잠금과 동일한 제스처 패턴
  공유. 이 브리프는 그 결정을 그대로 따름.
- 이 브리프는 01-folder-navigation 이후에 작업 — `FolderContentsView`가
  먼저 존재해야 그 화면의 행에도 스와이프 액션을 동일하게 적용할 수
  있음
- "잠금" 액션은 NO-001부터 일관되게 "UI만 구현, 실제 암호화 제외"로
  범위가 잡혀 있음 — 탭했을 때 정확히 어떤 피드백을 줄지(아무 동작
  없음 vs 토스트/알림)는 외이어프레임에 명시되어 있지 않으므로
  feature-implementer가 가장 단순한 방식으로 판단해서 구현하고 보고할 것

## Acceptance Criteria

- [ ] `HomeView`/`FolderContentsView`의 폴더·문서 행에서 좌로 스와이프
      시 편집/삭제 버튼이 노출됨
- [ ] "편집" 탭 시 폴더/문서 이름을 수정할 수 있음
- [ ] "삭제" 탭 시 확인 알림 후 soft delete되고 목록에서 사라짐
      (하위 항목이 있는 폴더는 포함 여부 확인 다이얼로그 표시)
- [ ] `DetailView` 블록에서 좌로 스와이프 시 "잠금" 액션 버튼이
      노출됨 (UI 표시만, 실제 암호화 없음)

## Open Questions / Follow-ups

- 없음
