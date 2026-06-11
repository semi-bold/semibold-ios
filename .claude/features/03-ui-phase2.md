# Feature: 03-ui-phase2

Status: draft

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
| Planning_2_FolderCreateFlow | TBD (sheet/VM name during implementation) | new folder creation |
| Planning_3_DocumentCreateFlow | TBD (sheet/VM name during implementation) | new document creation |

## Decisions & Deviations

_None yet — fill in as decisions are made during implementation._

## Acceptance Criteria

- [ ] `HomeView` matches `Screen_Home` layout (folder/document list)
- [ ] New folder flow implements all callouts in
      `Planning_2_FolderCreateFlow` and the PLANNING §5.2 state diagram
- [ ] New document flow implements all callouts in
      `Planning_3_DocumentCreateFlow` and the PLANNING §5.3 state diagram
- [ ] Created folders/documents persist via the `local-db-phase1`
      repository layer

## Open Questions / Follow-ups

- None yet
