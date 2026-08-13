# Feature: 03-divider-block-split

## Source

- `tasks/NO-007.md` §0 (배경 — the divider tap-edit bug, commit `9aba150`,
  that originally surfaced this whole refactor)
- Current code (ground truth): `semibold/Views/Screens/Detail/DetailScreen.swift`'s
  `BlockRow.isDivider`/`showsDividerRule` computed properties and the
  extensive doc comments on `BlockRow.body` and inside `editableBody`'s
  `ZStack` explaining the opacity/hit-testing fix — **read these in full
  before touching anything here**, they document a real, previously-fixed
  bug (tapping the rendered `---` rule didn't focus the field underneath)
  and the exact reasoning for why the current approach (always-mounted
  `ParagraphTextField`, rule drawn as an overlay on top, never swapped in
  a `Rectangle`-vs-field conditional) is correct.
- `02-block-row-shared-chrome` (must land first — this brief builds the
  divider's per-kind view on top of that brief's `BlockRowChrome`).

## Scope

- In scope:
  - A new `DividerBlockView` (naming your call) under
    `Views/Components/Block/`, using `02-block-row-shared-chrome`'s
    `BlockRowChrome`, that reproduces the current divider behavior
    exactly:
    - The `ParagraphTextField` stays permanently mounted (never
      conditionally inserted/removed based on focus).
    - Its text color is set to match the row's background
      (`showsDividerRule ? n900 : textColor`) rather than using SwiftUI
      opacity, for the hit-testing reason documented in the current code.
    - The rendered `---` rule `Rectangle` overlay has
      `allowsHitTesting(false)` so taps pass through to the real field.
    - `showsDividerRule` logic (`isDivider && focusedBlockId != item.id`)
      moves to `DividerBlockView`.
  - `DetailScreen.blockList`'s `ForEach` routes `divider` to
    `DividerBlockView`, completing the full split — after this brief,
    the old monolithic `BlockRow` struct no longer exists at all.
  - Fix the `BlockRow.dividerBody` doc-comment citations in
    `DetailViewModel+SlashCommand.swift` and
    `semiboldTests/SlashCommandConversionTests.swift` (deferred from
    `02-block-row-shared-chrome`) to reference `DividerBlockView`.
- Out of scope / deferred:
  - Any behavior change to the divider's tap-to-edit mechanism itself —
    this brief is a structural extraction, not a redesign. If you find
    yourself wanting to "improve" the mechanism, stop and flag it
    instead — the current approach was arrived at after a real bug fix
    (§0) and changing it risks reintroducing that bug.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `iOS_Editor` (wireframe) | `Views/Components/Block/DividerBlockView.swift` (new) | No visual/behavioral change |

## Decisions & Deviations

- This is deliberately the **last** of the three briefs in this set —
  see `02-block-row-shared-chrome`'s Decisions for why (lowest-risk
  placement for the one genuinely fragile block kind, once the chrome
  pattern is already proven on the 7 simpler kinds).
- Do not simplify or "clean up" the opacity-vs-textColor hit-testing
  workaround even if it looks like it could be done more simply with a
  different SwiftUI API — the current code's doc comment explains
  specifically why the obvious-looking alternative (opacity) silently
  breaks tap-to-focus. Preserve it as-is, just relocated.

## Acceptance Criteria

- [ ] `DividerBlockView` exists, uses `BlockRowChrome`, and reproduces
      today's exact divider rendering/tap-to-edit behavior.
- [ ] Tapping a divider's rendered `---` rule focuses the underlying
      text field and reveals the literal `"---"` for editing — manually
      verified in simulator (the exact bug this whole refactor started
      from, §0 — this is the one behavior in this entire brief set that
      must NOT regress).
- [ ] Tapping away from a focused divider re-shows the rendered rule.
- [ ] The old monolithic `BlockRow` struct is fully removed — `divider`
      was the last kind still routed through it.
- [ ] Doc-comment citations of `BlockRow.dividerBody`/`BlockRow.body`
      across the codebase now correctly reference `DividerBlockView`.
- [ ] `xcodegen generate` re-run, project builds clean, full test suite
      passes (pre-existing flaky `CoreDataTestStore` tests aside).

## Open Questions / Follow-ups

- None — this brief's scope is narrow and the target behavior is fully
  specified by the current code's own extensive doc comments.
