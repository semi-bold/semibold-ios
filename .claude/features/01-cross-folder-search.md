# Feature: 01-cross-folder-search

## Source

- `tasks/NO-008.md` §2.1 (검색: 문서 + 폴더 통합 결과), §3.2 (검색 중심으로 재편한 이유), §5.1 (검색 쿼리 — 현재 없음)
- Figma: `Planning_Nav_2_DrawerFlow` (FLOW-NAV-002), `iOS_SidebarDrawer_Search` screen — search bar with keyword "스터디" matching both a folder and documents, each document row showing its immediate parent folder name below the title.

## Scope

- In scope:
  - A repository-level search that, given a keyword, returns **all matching folders** (by name) and **all matching documents** (by title) across the *entire* Private Space — not scoped to one folder, and recursing through nested folders.
  - Each matched document result must carry its **immediate parent folder's name** (or `nil`/root indicator if it has no parent), so the UI (built in `03-sidebar-drawer`) can show it without a second lookup per row.
  - Soft-deleted folders/documents must be excluded, matching every other list query in the app.
- Out of scope / deferred:
  - The UI that calls this (search bar, results list) — that's `03-sidebar-drawer`.
  - Fuzzy/typo-tolerant matching — plain case-insensitive substring match is enough for this pass.
  - Ranking/relevance ordering beyond something simple (e.g. folders first, then documents alphabetically, or all by name) — no spec requirement for a specific order.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `Planning_Nav_2_DrawerFlow` (FLOW-NAV-002) §SpecRow_1/2 | `FolderRepository`, `DocumentRepository` | Data-layer only, no view in this brief |

## Decisions & Deviations

- `DocumentRepository`/`FolderRepository` currently only expose folder-scoped queries (`documents(in folderId:)`, `children(of parentId:)`) — there is no existing "whole tree" query to extend, so this is new, not a refactor of an existing method.
- Recommend adding `DocumentRepository.search(keyword:) throws -> [(document: Document, parentFolderName: String?)]` and `FolderRepository.search(keyword:) throws -> [Folder]` (or a single combined result type/struct if that reads cleaner in context — implementer's call, but keep the "parent folder name travels with the document result" requirement from Source).
- Case-insensitive substring match (`CONTAINS[cd]` in an `NSPredicate`, or fetch-then-filter if that's simpler given Core Data's predicate limitations) is sufficient — don't build a search index or FTS for this pass.

## Acceptance Criteria

- [ ] `DocumentRepository` exposes a method that returns every non-deleted document across all folders (recursively, not just direct children of one folder) whose title contains the given keyword (case-insensitive), each paired with its immediate parent folder's name (or an indicator it's at the root).
- [ ] `FolderRepository` exposes a method that returns every non-deleted folder across the whole tree whose name contains the given keyword (case-insensitive).
- [ ] An empty/blank keyword returns an empty result (not the whole space) — matches the UI's "show nothing until the user types" design (FLOW-NAV-002 §SpecRow_1).
- [ ] Unit tests cover: match in a nested (grandchild) folder, a document at the root (no parent folder), no matches, and soft-deleted items being excluded.

## Open Questions / Follow-ups

- None — this is a self-contained data-layer addition.
