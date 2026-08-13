# Feature: 03-depth-padding-rendering

## Source

- `tasks/NO-009.md` §3.2 "depth별 좌측 padding 렌더링", §4 (depth padding
  is a shared-layout concern, belongs in `BlockRowChrome`'s "공용 배관"
  layer, not per-kind styling).
- Depends on `02-indent-outdent-viewmodel` — depth derivation must exist
  before this brief can render it.
- No `Screen_*`/`Planning_N_*` wireframe defines nested-list indentation
  visually — no Figma frame exists yet for this (`tasks/NO-009.md` §5).
  Implement from `tasks/NO-009.md`'s description: each depth level adds
  one step of left indentation before the block's leading column/text,
  consistent with the flat left-indent-per-level pattern every other
  block-based editor (Notion, Word, etc.) uses — not a plan requiring a
  new visual design, just an extra `.padding(.leading, ...)` proportional
  to depth.

## Scope

- In scope:
  - `BlockRowChrome` (`Views/Components/Block/BlockRowChrome.swift`)
    gains a `depth: Int = 0` parameter and applies a per-level leading
    padding — additive to the existing `.padding(.horizontal,
    AppTheme.Spacing.md)`, not a replacement for it, so depth 0 renders
    pixel-identical to today.
  - `BulletedListBlockView.chrome(...)`/`NumberedListBlockView.chrome(
    ...)`/`ChecklistBlockView.chrome(...)` (the three list-kind
    factories) gain a `depth: Int` parameter, threaded through to
    `BlockRowChrome`. Every other kind's factory keeps `depth` defaulted
    to `0` (non-list kinds never nest, `tasks/NO-009.md` §2.2) — no
    signature change needed for `ParagraphBlockView`/`HeadingBlockView`/
    `QuoteBlockView`/`CodeBlockView`/`DividerBlockView`.
  - `DetailScreen.blockRow(for:content:)` passes the depth
    `02-indent-outdent-viewmodel`'s derivation function returns for
    `item.id` into the three list-kind factory calls.
- Out of scope / deferred:
  - The indent/outdent trigger UI itself (buttons, Tab key,
    `inputAccessoryView`) — `04`/`05`.
  - Any change to non-list block kinds' rendering.
  - A dedicated Figma frame for this — per `tasks/NO-009.md` §5 this
    still needs design confirmation for the on-screen toolbar button
    (`05`'s concern), but plain per-level left padding on existing list
    markers isn't a new visual component requiring its own design pass.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `iOS_Editor` (existing, no new frame) | `BlockRowChrome`, `BulletedListBlockView`/`NumberedListBlockView`/`ChecklistBlockView` | Depth adds left padding only; marker/checkbox visuals unchanged |

## Decisions & Deviations

- **Indent unit**: one depth level = `AppTheme.Spacing.lg` (24pt) of
  additional leading padding, matching the existing `AppTheme.Spacing.lg`
  `minWidth` already used for each list kind's marker/checkbox column
  (`BlockRowChrome.leadingColumnView`) — keeps a nested item's marker
  visually aligned one full marker-column-width in from its parent's,
  rather than an arbitrary new spacing value. This is an implementer
  judgment call in the absence of a Figma frame (`tasks/NO-009.md` §5)
  — flagged as an Open Question below in case the user wants to confirm
  or adjust the exact unit once it's visible on-device.
- **Where the padding is applied**: on `BlockRowChrome`'s outer
  container (before the existing `.padding(.horizontal, AppTheme.Spacing
  .md)`), not inside `leadingColumnView` — this indents the *entire*
  row (marker + text) rather than just the marker, matching how nested
  list indentation reads in every reference editor named in
  `tasks/NO-009.md`'s §3.2 framing (Notion/Word-style).
- Uniform concrete type is preserved: `depth` is a plain `Int` parameter
  on `BlockRowChrome`, not a generic/closure — consistent with
  `BlockRowChrome`'s existing design (see its doc comment on why every
  per-kind factory must return the same concrete type). This brief must
  not reintroduce a generic parameter.

## Acceptance Criteria

- [ ] `BlockRowChrome` renders additional leading padding proportional to
      a new `depth: Int = 0` parameter; `depth == 0` is visually
      identical to the pre-this-brief layout (regression check against
      `02-block-row-shared-chrome`'s already-reviewed padding/overlay
      behavior).
- [ ] `BulletedListBlockView`/`NumberedListBlockView`/`ChecklistBlockView`
      `.chrome(...)` factories accept and forward `depth`.
- [ ] `DetailScreen.blockRow(for:content:)` passes each list-kind item's
      derived depth (from `02`) into the corresponding factory call.
- [ ] A nested bulleted/numbered/checklist item (created by calling
      `indentBlock` from `02`, e.g. in a preview or manual test) renders
      visibly indented relative to its parent, at every depth reached by
      repeated indenting.
- [ ] Non-list block kinds are unaffected — no visual or signature change
      to `ParagraphBlockView`/`HeadingBlockView`/`QuoteBlockView`/
      `CodeBlockView`/`DividerBlockView`'s factories.

## Open Questions / Follow-ups

- The exact per-level indent amount (`AppTheme.Spacing.lg` chosen above)
  has no Figma frame to confirm against (`tasks/NO-009.md` §5) — this is
  a reasonable default, not a blocking question, but flag it for the
  user to eyeball once it's on-device and adjust if it doesn't feel
  right at 2+ levels deep.
