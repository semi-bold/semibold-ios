# Feature: 01-full-document-loading

## Source

- `tasks/NO-009.md` §3.2 "새로 필요한 것: 문서 전체 항목 로딩(현재는
  top-level만 fetch) — 신규 repository 메서드."
- No `Screen_*`/`Planning_N_*` wireframe — this brief is a pure data-layer
  change with no UI surface of its own.

## Scope

- In scope:
  - A new `DocumentItemRepository` method that fetches **every** live
    (non-soft-deleted) item for a document, at any depth, not just
    top-level (`parentItemId == nil`) ones — `children(documentId:
    parentItemId:)` (current code, `DocumentItemRepository.swift:49`)
    already fetches one level at a time; this brief adds the "give me the
    whole tree, flat" counterpart the editor needs once it stops
    restricting itself to top-level items.
  - `DetailViewModel.load()` (`DetailViewModel.swift:221`) switched to
    call the new method instead of `children(documentId:parentItemId:
    nil)`, so `items`/`textContents`/`marksByItemId`/`mediaContents` all
    now cover nested list items too.
  - Ordering: the flat result must be in **display order** — each item's
    siblings sorted by `orderKey` ascending, with children immediately
    following their parent (depth-first), since `DetailViewModel.items`
    is what `DetailScreen.blockList`'s `ForEach` renders top-to-bottom
    with no separate tree-walk step. Getting this ordering right here is
    what lets `02-indent-outdent-viewmodel`'s depth derivation and
    `insertBlock`/`mergeOrDeleteBlock`'s existing "previous/next item in
    the flat array" logic keep working unmodified for nested items.
- Out of scope / deferred:
  - `indentBlock`/`outdentBlock`, depth derivation, `numberedListNumber`'s
    sibling-scope fix — `02-indent-outdent-viewmodel`.
  - Any UI change (padding, indent controls) — `03-depth-padding-
    rendering` onward.
  - Query performance work beyond a single fetch — this is a personal,
    local-first, per-document editor; a document's total item count is
    small enough that one predicate-based fetch plus in-memory ordering
    is the right level of engineering here, matching every other
    repository method in this file.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| — (data layer only) | `DocumentItemRepository`, `DetailViewModel.load()` | No screen changes |

## Decisions & Deviations

- New method fetches the whole document's live items in one query
  (`documentId == %@ AND deletedAt == nil`, sorted by `orderKey`) and
  assembles the parent→children flat order in memory, rather than
  issuing one query per depth level — a document's item count is small
  enough (personal notes/lists, not enterprise documents) that this is
  simpler and fast enough, consistent with `children(documentId:
  parentItemId:)`'s existing single-query-per-call style right above it.
- Name it `allItems(documentId:)` (or equivalent) rather than overloading
  `children(documentId:parentItemId:)` — the existing method's contract
  ("one level, given a parent") stays useful on its own (nothing else in
  this brief removes callers of it), so this is an addition, not a
  replacement.
- `DetailViewModel`'s doc comment ("Only top-level items
  (`parentItemId == nil`) are loaded/edited here — nesting is out of
  this editor's scope", `DetailViewModel.swift:44`) is now stale once
  `load()` switches methods — update it to reflect that nested list
  items load too (still scoped to list-kind nesting per
  `tasks/NO-009.md` §2.1; this brief doesn't change what nesting means,
  only that it's now loaded).

## Acceptance Criteria

- [ ] `DocumentItemRepository` has a new method that returns every live
      item for a `documentId`, ordered depth-first by `orderKey` within
      each sibling group (top-level items in `orderKey` order, each
      followed immediately by its own children in `orderKey` order,
      recursively).
- [ ] `DetailViewModel.load()` calls the new method instead of
      `children(documentId:parentItemId:nil)`, so a document with nested
      list items (however they got into the database — this brief adds
      no way to create them yet) loads all of them into `items`/
      `textContents`/`marksByItemId`/`mediaContents`.
- [ ] `DetailViewModel`'s "nesting is out of this editor's scope" doc
      comment is updated to match.
- [ ] Existing tests (`DetailViewModelTests`, `ContentRepositoriesTests`)
      still pass unmodified where they only exercise top-level items —
      the new method's output must match the old one's for a document
      with no nested items.
- [ ] New repository-level test(s) covering: an empty document, a
      document with only top-level items (matches old behavior), and a
      document with at least one nested item (item with non-nil
      `parentItemId`) appearing immediately after its parent in the
      returned order.

## Open Questions / Follow-ups

- None — this brief is self-contained groundwork; `02-indent-outdent-
  viewmodel` is the first brief that actually creates nested items.
