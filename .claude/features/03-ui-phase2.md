# Feature: 03-ui-phase2

Status: in-progress

## Source

- Feature spec: none (from `TASKS.md` "UI — Phase 2", PLANNING.md §18
  Phase 2: 기본 UI 연결)
- Wireframes / planning specs:
  - `Screen_Home` (`../sketch-autokit/screens/wireframe.py`)
  - `Planning_2_FolderCreateFlow` (`../sketch-autokit/screens/planning.py`)
  - `Planning_3_DocumentCreateFlow` (`../sketch-autokit/screens/planning.py`)
- PLANNING.md sections: §4 (화면 구조), §5.2 (폴더 추가 플로우), §5.3
  (문서 추가 플로우), §6.1–6.2 (폴더/문서 기능 요구사항)
- SERVICE.md sections: access-policy notes for what's visible in the
  Private Layer folder/document list

## Scope

- In scope:
  - `Screen_Home` → folder/document list view (`HomeView`)
  - New folder flow per `Planning_2_FolderCreateFlow` / PLANNING §5.2
  - New document flow per `Planning_3_DocumentCreateFlow` / PLANNING §5.3
- Out of scope / deferred:
  - Block editor screen (`block-editor-phase3`)
  - Markdown rendering/conversion (`markdown-phase4`)

**Depends on:** `local-db-phase1` repository layer (folders/documents
CRUD) must exist before this can persist created items.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| Screen_Home | `HomeView` | folder/document list |
| Planning_2_FolderCreateFlow | `NewFolderSheet` / `NewFolderViewModel` | new folder creation |
| Planning_3_DocumentCreateFlow | TBD (sheet/VM name during implementation) | new document creation |

## Decisions & Deviations

- `Screen_Home` in `wireframe.py` (the "Example 1: Home screen" function,
  ~line 699) is a generic placeholder ("Welcome card", "Recent",
  "Categories") not specific to semi:bold's folder/document domain. The
  `iOS_PrivateSpace` artboard (same file) is the actual semi:bold-specific
  screen matching "folder/document list" — Private space badge, "+" add
  button, a Folders section and a Documents section, each made of
  60px-tall icon/title/subtitle/chevron rows. `HomeView` was built to
  match `iOS_PrivateSpace`'s structure/sizing while keeping the
  `Screen_Home` → `HomeView` name mapping from this brief.
- Section header labels are "Folders"/"Documents" (English, uppercased by
  the header style) rather than the wireframe's Korean "폴더"/"문서", to
  match the existing English-language UI/comment convention in this repo
  (e.g. `ContentView`, model doc comments).
- Per-row Secret-Lock icons (`icon_lock` in `iOS_PrivateSpace`, shown on
  some rows) are omitted — Secret Lock is a future per-item feature not
  yet modeled, so no field exists yet to drive that icon's visibility.
- `HomeView` is backed by a real `@Observable HomeViewModel` reading
  root-level folders/documents via `FolderRepository`/`DocumentRepository`
  (rather than mock data), since the repositories already exist from
  `local-db-phase1` and this avoids rework for AC4. Folder "N items"
  counts are stubbed at "0 items" (TODO) since computing child counts is
  out of scope for this item.
- Replaced the placeholder `ContentView` (brief 01) with `HomeView` as the
  app's root view in `SemiboldApp`, and removed `ContentView.swift` — its
  own doc comment said it would be replaced by the real home screen.
- The nav-bar "+" button is rendered as a 40x40 circular tap target
  (`primary.opacity(0.18)` background) rather than `iOS_PrivateSpace`'s
  bare 24x24 glyph — a touch-target affordance, not a missed element.
- `Planning_2_FolderCreateFlow`'s destination artboard is `iOS_AddMenu`
  (the "+" action sheet with "새 폴더 만들기" / "새 문서 만들기" / "취소").
  The "+" button now opens a `confirmationDialog` with "New Folder" /
  "New Document" / "Cancel" matching that artboard's three options
  (callouts ④/⑤). "New Folder" leads into the name-entry step; "New
  Document" stays a TODO no-op pending `Planning_3_DocumentCreateFlow`
  (AC3).
- The mermaid diagram's "폴더 이름 입력" step (B) has no dedicated
  wireframe artboard in `Planning_2_FolderCreateFlow` (only
  `iOS_PrivateSpace` and `iOS_AddMenu` are shown), so `NewFolderSheet` is
  a standard iOS form sheet (`NavigationStack` + `TextField` + Cancel/
  Create toolbar buttons) built from `AppTheme` tokens rather than a
  pixel match to a specific artboard.
- Validation ("이름 유효?" / "에러 표시") is name-non-empty-after-trim:
  an empty/whitespace-only name shows an inline error and keeps the sheet
  open; the Create button is also disabled in that state as a redundant
  guard. A repository-write failure shows a generic "couldn't save"
  error and likewise keeps the sheet open, satisfying the diagram's
  `D → B` loop for both validation and persistence failures.
- "생성된 폴더 선택 상태로 전환" (select the newly created folder) is
  implemented as `HomeViewModel.selectedFolderId`, which highlights the
  new folder's row (`surface2` background) after the list reloads.
  Navigating *into* the folder isn't implemented yet — there's no folder
  detail/contents screen in this brief's scope — so "selected" is shown
  as a list highlight rather than a navigation push.

## Acceptance Criteria

- [x] `HomeView` matches `Screen_Home` layout (folder/document list)
- [x] New folder flow implements all callouts in
      `Planning_2_FolderCreateFlow` and the PLANNING §5.2 state diagram
- [ ] New document flow implements all callouts in
      `Planning_3_DocumentCreateFlow` and the PLANNING §5.3 state diagram
- [ ] Created folders/documents persist via the `local-db-phase1`
      repository layer

## Open Questions / Follow-ups

- `HomeViewModel.selectedFolderId` (new-folder highlight) is never
  cleared, so it persists indefinitely rather than being a transient
  "selected" state per PLANNING §5.2. Revisit once a folder-detail
  screen exists (clear on navigation, or add a timeout/dismiss).
