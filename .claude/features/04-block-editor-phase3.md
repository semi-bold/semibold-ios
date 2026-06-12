# Feature: 04-block-editor-phase3

Status: in-progress

## Source

- Feature spec: none (from `TASKS.md` "Block editor — Phase 3",
  PLANNING.md §18 Phase 3: Block Editor)
- Wireframes / planning specs:
  - `Screen_Detail` (`../sketch-autokit/screens/wireframe.py`)
  - `Planning_4_BlockCreateFlow` (`../sketch-autokit/screens/planning.py`)
- PLANNING.md sections: §5.4 (블록 추가 플로우), §6.3 (블록 추가 기능
  요구사항, including 저장 원칙 §6.3 하단), §13.1 (기본 키 동작)
- SERVICE.md sections: N/A unless block-level access policy applies

## Scope

- In scope:
  - `Screen_Detail` → document editor view
  - Paragraph block input, Enter-to-create new block, autosave,
    delete/merge, reorder — per `Planning_4_BlockCreateFlow` and PLANNING
    §5.4/§6.3
- Out of scope / deferred:
  - Heading/list/checklist/blockquote/code block conversions and inline
    marks (`markdown-phase4`)
  - Drag & drop reordering UI, macOS shortcuts (`quality-phase5`)

**Depends on:** `local-db-phase1` repository layer (`document_blocks`
CRUD) and `ui-phase2` (navigation into a document from `HomeView`).

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| Screen_Detail | `DetailView` (or per CLAUDE.md §1 naming) | document editor |
| Planning_4_BlockCreateFlow | TBD (block view-model name) | block create/edit/delete/reorder |

## Decisions & Deviations

- `Screen_Detail` in `wireframe.py` (lines ~86-137, ~787-841) is a generic
  "detail view" example artboard, unrelated to the document editor — same
  situation as brief 03's `Screen_Home`. The real document-editor artboard
  is `iOS_Editor` (`wireframe.py` lines ~296-422), which is also what
  `Planning_4_BlockCreateFlow`'s callouts reference. `DetailView` was built
  against `iOS_Editor`'s static layout (custom nav bar + back button,
  title area with title/date, divider, block list), keeping the brief's
  `DetailView` type name while citing `iOS_Editor` as the real reference.
- `DetailView`'s nav bar omits `iOS_Editor`'s `DocLockBtn` (Secret-Lock
  toggle) — out of scope per `Planning_4_BlockCreateFlow` callout ④.
- Back button shows generic "< Back" rather than the wireframe's literal
  "< 일상" (a specific folder name) — `HomeView` is a flat root-level list
  with no folder-navigation context to source a folder name from.
- `iOS_Editor`'s `KeyboardToolbar`/`KeyboardArea` (shown during text input)
  are deferred to AC2 (paragraph input), not part of this static layout.
- Tapping a document row in `HomeView` now navigates to `DetailView` via
  `NavigationLink(value:)`/`navigationDestination(for: Document.self)`
  (added `Hashable` to `Document`) — needed since `DetailView` has no
  entry point otherwise. Block rows render read-only as plain
  `markdownSource` text for now (`BlockRow`); type-specific styling is
  `markdown-phase4`. A document with zero blocks shows a "Start
  writing…" placeholder — creating the first empty block is AC2's scope.

## Acceptance Criteria

- [x] `DetailView` matches `Screen_Detail` layout
- [ ] Paragraph block input + Enter-to-create new block works
- [ ] Autosave per PLANNING §11 (자동 저장 정책) basic policy
- [ ] Block delete/merge and reorder implemented per
      `Planning_4_BlockCreateFlow` callouts and PLANNING §5.4 diagram
- [ ] Blocks persist via `document_blocks` repository from
      `local-db-phase1`

## Open Questions / Follow-ups

- None yet
