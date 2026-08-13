# Feature: 02-indent-outdent-viewmodel

## Source

- `tasks/NO-009.md` §2.1 (scope: list-kind blocks only, one-step button
  action, no artificial depth cap), §3.1 (real tree via `parentItemId`,
  no depth cap in code), §3.2 (flat array + depth label, new
  `indentBlock`/`outdentBlock` methods, `numberedListNumber` sibling-scope
  fix).
- Depends on `01-full-document-loading` — `items` must already include
  nested items before indent/outdent has anything to operate on.
- No `Screen_*`/`Planning_N_*` wireframe — this brief is `DetailViewModel`
  logic; the buttons/keys that call it land in `04`/`05`.

## Scope

- In scope:
  - `indentBlock(_ blockId: String)`: makes the item's immediate previous
    sibling (same `parentItemId`, in display order) its new parent —
    only when the block is a list-kind item (`bulletedListItem`/
    `numberedListItem`/`checklist`, `tasks/NO-009.md` §2.1) **and** a
    previous sibling exists **and** that previous sibling is the *same*
    list kind (indenting a bulleted item under a numbered one, or under
    a non-list block, isn't meaningful — see Decisions). No-op otherwise.
  - `outdentBlock(_ blockId: String)`: promotes the item to its current
    parent's own `parentItemId` (one level up), positioned immediately
    after that former parent in `orderKey` order. No-op if the block has
    no parent (already top-level).
  - Both persist immediately (structural edit, PLANNING §11.2 "블록
    생성/삭제/순서 변경: 즉시 저장"), matching `mergeOrDeleteBlock`'s/
    `insertBlock`'s existing pattern — no depth cap in either method's
    logic (`tasks/NO-009.md` §3.1).
  - A `depth(forItemId:)` (or equivalent per-item derived value) that
    walks `parentItemId` chains within the already-loaded `items` array —
    no new query, since `01-full-document-loading` already loaded the
    whole tree into memory.
  - `numberedListNumber(forItemId:)` (`DetailViewModel.swift:310`) fixed
    to only count consecutive siblings **sharing the same
    `parentItemId`** as the item being numbered — today it counts
    backwards through `items` regardless of parent, which is already
    wrong for two adjacent-but-unrelated numbered lists and would become
    visibly wrong the moment nested numbered lists exist.
- Out of scope / deferred:
  - Any UI (depth padding, indent buttons, Tab key) — `03` onward.
  - Multi-block-at-once indent — single block per call only
    (`tasks/NO-009.md` §2.2, that's NO-010's territory if ever).
  - Drag-and-drop reparenting — out of scope permanently (session memory
    `project_block_editor_no_drag_reorder`).
  - Nesting anything other than a list item under a same-kind list item
    (e.g. a paragraph under a bulleted item, Notion-toggle-style) —
    `tasks/NO-009.md` §2.2 excludes this explicitly.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| — (view-model logic only) | `DetailViewModel.indentBlock(_:)` / `.outdentBlock(_:)` / depth derivation | No screen changes; `03` wires this into rendering |

## Decisions & Deviations

- **Indent requires a same-kind previous sibling.** `tasks/NO-009.md`
  §2.1 only says "바로 위 형제를 새 부모로" (the immediately preceding
  sibling becomes the new parent) without addressing what happens when
  that sibling is a different block kind (or not a list at all). Since
  §2.2 explicitly excludes "임의 블록 타입 중첩" (nesting under an
  arbitrary block type) and this feature only means "list item nested
  under a same-kind list item," indenting is a no-op unless the
  immediately preceding sibling is the same list `textKind`. This is a
  deviation-by-clarification, not a scope change — flagged here because
  the spec didn't spell out this edge case and an implementer could
  otherwise pick a different (wrong) interpretation.
- **`orderKey` on indent/outdent**: indenting assigns the item a fresh
  `orderKey` among its new parent's children via `OrderKey.between`
  (appended at the end, i.e. `OrderKey.between(lastCurrentChild?
  .orderKey, nil)`, since indenting always nests under the sibling
  directly above — there's nothing already positioned after it under
  that new parent). Outdenting assigns a fresh `orderKey` among the new
  (grandparent) parent's children, positioned immediately after the
  item's former parent (`OrderKey.between(formerParent.orderKey,
  nextSiblingAfterFormerParent?.orderKey)`) — this is what "promote to
  right after the parent" means in display order.
- **Depth has no stored field** — it's derived by walking
  `parentItemId` through the in-memory `items` array each time it's
  needed (`tasks/NO-009.md` §3.2's "depth는 라벨만 추가"), not persisted
  on `DocumentItem`. Keeps the data model unchanged and avoids a second
  source of truth that could drift from the actual `parentItemId` chain.
- **`numberedListNumber` fix is a correctness fix bundled into this
  brief**, not a separate one — it only becomes observably wrong once
  nested numbered lists can exist, which this brief is what first makes
  possible, and the fix is a one-line predicate change
  (`tasks/NO-009.md` §3.2) not worth its own brief.

## Acceptance Criteria

- [ ] `DetailViewModel.indentBlock(_:)` exists: no-ops unless the target
      is a list-kind item with an immediately preceding same-kind-list
      sibling; otherwise reassigns `parentItemId` to that sibling's id,
      computes a fresh trailing `orderKey` among the new parent's
      existing children, persists immediately, and updates `items` (both
      structural mutation and in-memory order) so the item now renders
      immediately after its new parent's other children.
- [ ] `DetailViewModel.outdentBlock(_:)` exists: no-ops if the target has
      no `parentItemId`; otherwise reassigns `parentItemId` to the
      current parent's own `parentItemId`, computes a fresh `orderKey`
      placing it immediately after the former parent among the new
      parent's children, persists immediately, and updates `items`.
- [ ] Repeated indent/outdent calls work at arbitrary depth — no
      hardcoded depth ceiling anywhere in either method.
- [ ] A depth-derivation function/property is available for `03` to
      consume, correct for items at any nesting level, backed only by
      the in-memory `items` array (no new query per call).
- [ ] `numberedListNumber(forItemId:)` only counts consecutive siblings
      sharing the same `parentItemId` as the target item.
- [ ] Unit tests: indent with no previous sibling (no-op), indent with a
      different-kind previous sibling (no-op), indent with a same-kind
      previous sibling (succeeds, `parentItemId` updated, `orderKey`
      places it correctly), outdent on a top-level item (no-op), outdent
      on a nested item (succeeds, promoted correctly, positioned right
      after former parent), indent→indent→outdent→outdent round-trip
      restores the original flat position, and `numberedListNumber` with
      two sibling groups (one nested under a list item, one top-level)
      numbering independently.

## Open Questions / Follow-ups

- None blocking — the "same-kind previous sibling required for indent"
  rule above is this brief's own interpretation filling a spec gap, not
  a question that needs to bounce back to the user before implementing,
  but flag it in the PR notes in case the user wants a different edge-case
  rule after seeing it in practice.
