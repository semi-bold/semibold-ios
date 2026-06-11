# Feature: 02-local-db-phase1

Status: draft

## Source

- Feature spec: none (from `TASKS.md` "Local DB — Phase 1", PLANNING.md
  §18 Phase 1: 기본 저장 구조)
- Wireframes / planning specs: N/A — data layer, no screen of its own
- PLANNING.md sections: §9 (로컬 DB 설계 초안 — `folders`, `documents`,
  `document_blocks`, recommended indexes), §6 (기능 요구사항 for
  field-level requirements)
- SERVICE.md sections: review for any Private/Secret access-policy fields
  that need to exist on these tables from the start

## Scope

- In scope:
  - GRDB `DatabaseManager` + versioned `DatabaseMigrator`
  - `folders` / `documents` / `document_blocks` tables per PLANNING.md §9
    (including recommended indexes, §9.4)
  - Repository layer: CRUD for folders/documents/blocks
- Out of scope / deferred:
  - Any UI wiring (handled in `ui-phase2`, `block-editor-phase3`)
  - Markdown conversion logic (`markdown-phase4`)

## Screens & Flows

N/A — data layer only. `ui-phase2` and `block-editor-phase3` depend on
the repository layer produced here.

## Decisions & Deviations

_None yet — fill in as decisions are made during implementation._

## Acceptance Criteria

- [ ] `DatabaseManager` sets up GRDB connection + versioned
      `DatabaseMigrator`
- [ ] `folders`, `documents`, `document_blocks` tables created exactly
      per PLANNING.md §9 (field names, types, soft-delete columns)
- [ ] Recommended indexes from §9.4 applied
- [ ] Repository layer provides CRUD for folders/documents/blocks, named
      per PLANNING.md §9 field names (`sortOrder`, `parentId`,
      `contentJSON`, `markdownSource`, …)

## Open Questions / Follow-ups

- None yet
