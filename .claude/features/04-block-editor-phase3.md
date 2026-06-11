# Feature: 04-block-editor-phase3

Status: draft

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

_None yet — fill in as decisions are made during implementation._

## Acceptance Criteria

- [ ] `DetailView` matches `Screen_Detail` layout
- [ ] Paragraph block input + Enter-to-create new block works
- [ ] Autosave per PLANNING §11 (자동 저장 정책) basic policy
- [ ] Block delete/merge and reorder implemented per
      `Planning_4_BlockCreateFlow` callouts and PLANNING §5.4 diagram
- [ ] Blocks persist via `document_blocks` repository from
      `local-db-phase1`

## Open Questions / Follow-ups

- None yet
