# Feature: 02-block-row-shared-chrome

## Source

- `tasks/NO-007.md` §0 (배경), §1 예비 방향 (미확정 — this brief is where
  it gets confirmed for 7 of the 8 kinds; divider is deliberately excluded,
  see Scope)
- Current code (ground truth for what's being split):
  `semibold/Views/Screens/Detail/DetailScreen.swift`'s private `BlockRow`
  struct (after `01-detail-screen-views-migration` lands) — `textStyle`,
  `listMarker`, `textColor`, `isCodeBlock` computed properties, and the
  `if let listMarker { … } else if content.textKind == .checklist { … }
  else if content.textKind == .quote { … }` branch inside `editableBody`.

## Scope

- In scope — for these 7 kinds only: `paragraph`, `heading`, `quote`,
  `checklist`, `bulletedListItem`, `numberedListItem`, `codeBlock`.
  - New shared component (name your call, e.g. `BlockRowChrome`) under
    `Views/Components/Block/` holding what's genuinely common across all
    8 kinds today: the outer `VStack`/`HStack` scaffold, the leading
    marker/checkbox/quote-bar column's shared layout (`frame(minWidth:
    AppTheme.Spacing.lg, ...)`), the `ParagraphTextField` wiring (focus
    binding, `onTextChange`/`onEnter`/`onBackspaceAtStart`,
    `cursorOffsetToApply`), and the row's outer padding/background
    (`isCodeBlock ? n700 : n900`).
  - New per-kind view files under `Views/Components/Block/` for each of
    the 7 kinds above — each owns only what actually varies for that
    kind: `ParagraphBlockView`/`HeadingBlockView`/`QuoteBlockView`/
    `ChecklistBlockView`/`BulletedListBlockView`/`NumberedListBlockView`/
    `CodeBlockView` (naming your call, keep it consistent). What varies
    per kind, concretely:
    - `textStyle` (heading uses level 1-3 typography, everything else
      `.body`)
    - leading-column content (bullet `•`, number `"\(n)."`, checkbox
      button, quote's vertical rule `Rectangle`, or nothing)
    - `textColor` (quote dims to `.secondary`, everything else
      `.primary`)
    - `isMonospaced` (code block only)
  - `DetailScreen.blockList`'s `ForEach` routes to the shared chrome +
    per-kind view based on `content.textKind`, replacing today's single
    `BlockRow` struct for these 7 kinds.
  - Update the `BlockRow.dividerBody`/`BlockRow.body` doc-comment
    citations in `DetailViewModel.swift`, `DetailViewModel+SlashCommand.swift`,
    and `semiboldTests/SlashCommandConversionTests.swift` to reference
    the new structure (they currently cite a `dividerBody` member that
    doesn't actually exist in the current single-`BlockRow` code — this
    brief is a reasonable point to fix that drift, at least for whatever
    these comments should now point to for the 7 non-divider kinds; the
    divider-specific citations get fixed in `03-divider-block-split`
    instead, once that view actually exists).
- Out of scope / deferred:
  - **`divider` stays exactly as-is in this brief** — still routed
    through the old inline logic (or, implementer's call, temporarily
    still going through a slimmed-down remnant of the old `BlockRow` for
    just this one kind) until `03-divider-block-split`. Divider's
    render↔edit toggle (`showsDividerRule`, the opacity/hit-testing fix
    documented at length in the current code) is uniquely fragile —
    isolating it into its own brief, built on top of this brief's
    already-proven shared chrome, is lower-risk than doing it first with
    no chrome precedent yet (`tasks/NO-007.md` doesn't mandate an order;
    this is this brief-set's own sequencing call — see Decisions).
  - `TextItemKind` (the data-layer string-constant namespace) — untouched,
    per `tasks/NO-007.md`'s own preliminary direction.
  - Any `DetailViewModel` logic change (`numberedListNumber`,
    `updateBlockText`, etc.) — this is a pure View-layer split, the
    ViewModel's public surface doesn't change.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `iOS_Editor` (wireframe) | `Views/Components/Block/*BlockView.swift` (new), `Views/Components/Block/BlockRowChrome.swift` (new) | No visual change — same wireframe, internal structure only |

## Decisions & Deviations

- **Divider excluded from this brief** — see Scope. `tasks/NO-007.md`'s
  own preliminary direction guessed divider "가능성이 높다" as the first
  split target; this brief-set deliberately does it last instead, once a
  working shared-chrome pattern already exists to build on. Flag to
  `swift-reviewer`/human if this ordering call should be revisited.
- **Shared-chrome boundary**: layout/plumbing that's identical across all
  8 kinds → chrome. Anything that varies by kind (even if only for 1-2
  kinds, like the checkbox or quote bar) → per-kind view. Don't put
  kind-specific `if content.textKind == ...` branches back inside the
  chrome — that's the exact anti-pattern `tasks/NO-007.md` §0 identified.
- Per-kind views take whatever subset of `BlockRow`'s current parameters
  they actually need (e.g. `ChecklistBlockView` needs `isChecked`/
  `onToggleChecklist`, `NumberedListBlockView` needs
  `numberedListNumber`, most others need neither) — don't force every
  per-kind view to accept the full old parameter list for uniformity.

## Acceptance Criteria

- [ ] `BlockRowChrome` (or equivalently-named shared component) exists
      under `Views/Components/Block/`, holds only genuinely-shared
      layout/plumbing (see Scope), and takes no `content.textKind`
      branch itself.
- [ ] 7 new per-kind view files exist under `Views/Components/Block/`,
      one per kind listed in Scope, each reproducing that kind's exact
      current visual output (marker, color, style, monospace) with zero
      pixel/behavior difference from today.
- [ ] `DetailScreen.blockList`'s `ForEach` routes each of these 7 kinds
      to its new per-kind view via the shared chrome; `divider` still
      renders exactly as it does today (whatever internal path is
      simplest — see Scope's divider note).
- [ ] Typing Markdown shortcuts that convert a block to any of these 7
      kinds (`- `, `1. `, `- [ ] `, `# `/`## `/`### `, `> `, code fence)
      still works and renders identically — manually verified in
      simulator (this is a View-layer refactor with no dedicated View
      tests in this codebase's existing test convention; verify via the
      app, not new unit tests).
- [ ] Keyboard-focus behavior (tap a row → keyboard appears, cursor at
      tap point; Enter/Backspace/merge) is unchanged for all 7 kinds.
- [ ] `xcodegen generate` re-run, project builds clean, full test suite
      passes (pre-existing flaky `CoreDataTestStore` tests aside).

## Open Questions / Follow-ups

- Exact per-kind view file names — implementer's call, listed above as a
  starting suggestion, keep them consistent with each other.
- Whether `BlockRowChrome` takes the per-kind content as a
  `@ViewBuilder` trailing closure (slot-based, matching this session's
  `ContentListLayout`/`NavBar` precedent) vs. an enum-driven internal
  switch — recommend the `@ViewBuilder` slot approach for consistency
  with those two, but implementer/reviewer can deviate with reasoning if
  the per-kind parameter variance (checklist's `onToggleChecklist`,
  numbered list's `numberedListNumber`) makes that awkward.
