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
| Planning_3_DocumentCreateFlow | `NewDocumentSheet` / `NewDocumentViewModel` | new document creation |

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
- `Planning_3_DocumentCreateFlow`'s destination sequence is
  `iOS_PrivateSpace → iOS_AddMenu → iOS_Editor` (callouts ①–⑤), unlike
  `Planning_2_FolderCreateFlow` whose destination is just `iOS_AddMenu`.
  `iOS_AddMenu` is shared between the two flows (same "새 폴더 만들기" /
  "새 문서 만들기" sheet, callouts ④/⑤ in Planning_2 vs. ③ in Planning_3);
  "새 문서 만들기" (callout ③) is the entry point for this flow, already
  wired up in AC2 via the shared `confirmationDialog`. The `iOS_Editor`
  destination (callouts ④/⑤ — title input area, first empty block) is out
  of scope for this brief (`block-editor-phase3`), so this item stops at
  "documents row 생성" → "문서 목록 갱신" → "선택 상태로 전환", the part of
  PLANNING §5.3's diagram (A→B→C/D→E) that's actually buildable here.
- §5.3 step B ("현재 선택된 폴더 있음?") has no "선택된 폴더" concept in
  `HomeView` yet (no folder navigation/detail screen), so it always takes
  the "없음" branch (D): new documents are created with `folderId: nil`
  (root), matching `HomeViewModel.documents`'s root-level list.
- §5.3 steps F–H ("빈 document editor 열기" → "제목 입력" → "자동 저장")
  happen inside the Editor in the full flow, but the Editor is out of
  scope here. `NewDocumentSheet` collects the title *before* creating the
  `documents` row instead — a pre-creation substitute for the in-Editor
  title field, analogous to how `NewFolderSheet` substitutes for §5.2's
  "폴더 이름 입력" step (B), which also has no dedicated wireframe
  artboard. Unlike folder names, an empty title is valid: leaving it blank
  saves the document as "Untitled" (`Document`'s default, PLANNING §6.2
  "제목이 없을 경우 Untitled 사용"), so there's no inline validation error
  and the Create button is never disabled.
- "문서 목록 갱신" → "선택 상태로 전환" (refresh the list, select the new
  document) is implemented as `HomeViewModel.selectedDocumentId`,
  generalizing AC2's `selectedFolderId` pattern to documents — the new
  document's row gets the same `surface2` highlight after the list
  reloads. Same open-question as `selectedFolderId`: it isn't cleared, see
  Open Questions.

## Acceptance Criteria

- [x] `HomeView` matches `Screen_Home` layout (folder/document list)
- [x] New folder flow implements all callouts in
      `Planning_2_FolderCreateFlow` and the PLANNING §5.2 state diagram
- [x] New document flow implements all callouts in
      `Planning_3_DocumentCreateFlow` and the PLANNING §5.3 state diagram
- [ ] Created folders/documents persist via the `local-db-phase1`
      repository layer

## Open Questions / Follow-ups

- `HomeViewModel.selectedFolderId` / `selectedDocumentId` (new-item
  highlights) are never cleared, so they persist indefinitely rather than
  being a transient "selected" state per PLANNING §5.2/§5.3. Revisit once
  a folder-detail/document-editor screen exists (clear on navigation, or
  add a timeout/dismiss).
- `Planning_3_DocumentCreateFlow`'s `iOS_Editor` destination (callouts
  ④/⑤ — title input area focus, first empty block) and PLANNING §5.3
  steps F–H (open empty editor → title input → autosave) are deferred to
  `block-editor-phase3`. `NewDocumentSheet` covers title entry as a
  pre-creation substitute (see Decisions above); revisit whether the
  Editor should also support editing the title once it exists, or whether
  this sheet remains the only title-entry point.
