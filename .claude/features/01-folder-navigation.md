# Feature: 01-folder-navigation

Status: in-progress

## Source

- Feature spec (if provided externally): none
- Wireframes / planning specs: `iOS_FolderContents` (`ios_foldercontents`,
  wireframe.py), `Planning_6_FolderNavigationFlow` (planning.py)
- `tasks/<work-code>.md` section (primary): `docs/tasks/NO-003.md` §1.1,
  §2.1, §3.1
- PLANNING.md sections (legacy fallback): §4.2 (iOS 화면 방향,
  NavigationStack 구조), §5.2/§5.3 (폴더/문서 추가 플로우), §6.1/§6.2
  (폴더/문서 요구사항)
- SERVICE.md sections: none

## Scope

- In scope:
  - `FolderContentsView`(가칭) 구현 — `iOS_FolderContents` 와이어프레임
    1:1 매칭: NavBar("< Semi:bold" 뒤로가기 + 현재 폴더명 중앙 제목 +
    "+" 우측), 하위 폴더 섹션, 문서 섹션
  - 폴더 탭 내비게이션 — `NavigationStack` push 방식 (NO-003 §1.1 결정
    사항: 사이드바 드로어 아님)
  - `HomeView`에서 폴더 행 탭 시 `FolderContentsView` push
  - `FolderContentsView`에서 하위 폴더 행 탭 시 같은 화면이 재귀적으로
    push (중첩 폴더 탐색)
  - `FolderContentsView`에서 문서 행 탭 시 `DetailView` push
  - `FolderContentsView`의 "+" 버튼 — 현재 폴더 내부에 하위 폴더/문서
    생성 (기존 `HomeView`의 `iOS_AddMenu`/`NewFolderSheet`/
    `NewDocumentSheet` 재사용, `parentId`/`folderId`를 현재 폴더로 지정)
  - `DetailView`의 NavBar 뒤로가기 라벨이 현재 문서가 속한 폴더명을
    표시하도록 수정 (와이어프레임 `ios_editor`의 "< 일상" 참고) — 루트
    문서는 "< Semi:bold"(또는 동등 라벨) 유지
- Out of scope / deferred:
  - 사이드바 드로어 (`ios_sidebardrawer`) — Public Space 도입 전까지
    보류 (NO-003 §1.2, §3.3)
  - 스와이프 액션(편집/삭제) — 02번 브리프
  - 폴더/문서 실제 이동(move) 기능 — 이번 범위는 탐색만, 이동은 별도
  - 폴더 내부 하위 폴더/문서 개수 표시 — `HomeView`의 기존 "0 items"
    더미와 동일한 한계를 그대로 가짐 (별도 브리프에서 다룰 사항)

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `iOS_FolderContents` | `FolderContentsView` | NavBar + 하위 폴더 섹션 + 문서 섹션 |
| `Planning_6_FolderNavigationFlow` | `FolderContentsView` 내비게이션 로직 | 콜아웃 ①–⑤ 순서대로 구현 |

## Decisions & Deviations

- 내비게이션 방식은 NO-003 §1.1에서 이미 결정됨 — `NavigationStack`
  push, 사이드바 드로어 아님. 이 브리프는 그 결정을 그대로 따름.
- `HomeView`/`FolderContentsView`가 폴더/문서 목록을 보여주는 핵심
  구조(섹션 헤더 + 행 스타일)를 공유하므로, 가능한 한 공통 컴포넌트로
  추출할 것 — 두 화면에 동일한 `FolderRow`/`DocumentRow`/
  `sectionHeader`/`emptyRow`를 중복 구현하지 말 것
- 공통 `sectionHeader` 추출과 함께, 현재 `HomeView`의 섹션 헤더 텍스트
  "Folders"/"Documents"(영어)를 `ios_privatespace` 와이어프레임
  명시대로 "폴더"/"문서"(한글)로 수정 — sketch 명세 재검토에서 발견된
  기존 불일치, 공통 컴포넌트를 만드는 이 작업과 함께 고치는 것이 합리적
- `DetailView`의 뒤로가기 라벨에 폴더명을 표시하려면 `Document` 모델이
  자신의 부모 폴더 이름을 알아야 함 — 현재 `Document`는 `folderId`만
  갖고 있으므로, `DetailView`/`DetailViewModel`이 폴더명을 조회하는
  방법(예: `FolderRepository.find(id:)` 호출, 또는 호출부에서 폴더명을
  미리 전달)을 정해야 함. 구체적인 방법은 feature-implementer가 기존
  코드 구조에 맞게 판단

## Acceptance Criteria

- [ ] `FolderContentsView`가 `iOS_FolderContents` 와이어프레임과 1:1
      매칭됨 (NavBar, 하위 폴더 섹션, 문서 섹션)
- [ ] `HomeView`/`FolderContentsView`에서 폴더 행 탭 시
      `FolderContentsView`가 push되고, 중첩 폴더도 동일하게 재귀 동작함
- [ ] `FolderContentsView`에서 문서 행 탭 시 `DetailView`가 push됨
- [ ] `FolderContentsView`의 "+" 버튼으로 현재 폴더 내부에 하위
      폴더/문서를 생성할 수 있음
- [ ] `DetailView`의 뒤로가기 라벨이 문서가 속한 폴더명을 표시함
      (루트 문서는 기존 라벨 유지)
- [ ] `HomeView`/`FolderContentsView`의 섹션 헤더가 와이어프레임대로
      "폴더"/"문서"(한글)로 표시됨

## Open Questions / Follow-ups

- 없음
