# Feature: 02-local-db-phase1

Status: in-progress

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

- `DatabaseManager` (`semibold/Data/DatabaseManager.swift`) opens a GRDB
  `DatabaseQueue` at `semibold.sqlite` in Application Support (or a
  caller-supplied path, e.g. `:memory:` for tests/previews) and runs
  `AppMigrations.migrator.migrate(dbQueue)` on init.
- `AppMigrations` (`semibold/Data/AppMigrations.swift`) holds the
  versioned `DatabaseMigrator`. Its first migration, `v1_createCoreTables`,
  creates `folders`, `documents`, and `document_blocks` (field names
  matching PLANNING §9: `parentId`, `sortOrder`, `contentJSON`,
  `markdownSource`, `createdAt`/`updatedAt`/`deletedAt`, …) plus the five
  recommended indexes from §9.4 (`idx_folders_parent_id`,
  `idx_documents_folder_id`, `idx_blocks_document_id`,
  `idx_blocks_parent_id`, `idx_blocks_sort_order`). This satisfies AC1
  (migrator setup) and incidentally covers most of AC2/AC3 — repository
  layer (AC4) and any remaining schema verification are still open.

## Acceptance Criteria

- [x] `DatabaseManager` sets up GRDB connection + versioned
      `DatabaseMigrator`
- [x] `folders`, `documents`, `document_blocks` tables created exactly
      per PLANNING.md §9 (field names, types, soft-delete columns)
- [x] Recommended indexes from §9.4 applied
- [ ] Repository layer provides CRUD for folders/documents/blocks, named
      per PLANNING.md §9 field names (`sortOrder`, `parentId`,
      `contentJSON`, `markdownSource`, …)

## Open Questions / Follow-ups

- `AppMigrations.swift`'s FK declarations use `onDelete: .none` (= no
  explicit `ON DELETE` clause / SQLite default). Reads as if it's a
  deliberate "do nothing" policy; revisit alongside AC4's repository
  delete semantics (soft-delete via `deletedAt` is the intended path) —
  either drop `onDelete:` or add a clarifying comment then.
