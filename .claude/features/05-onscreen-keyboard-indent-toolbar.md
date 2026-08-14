# Feature: 05-onscreen-keyboard-indent-toolbar

## Source

- `tasks/NO-009.md` §3.3 "iPhone 기본 온스크린 키보드에는 물리 Tab 키가
  없다... `UITextView.inputAccessoryView`(키보드 위에 뜨는 커스텀
  툴바)에 들여쓰기/내어쓰기 아이콘 버튼을 추가해야 한다. 하드웨어 Tab과
  이 버튼 둘 다 같은 `indentBlock`/`outdentBlock`을 호출한다", §5 "온스크린
  키보드 인디케이터 버튼의 정확한 UI/배치는 Figma 디자인이 아직 없다 —
  착수 전 확인 필요."
- Depends on `02-indent-outdent-viewmodel` (calls the same
  `indentBlock`/`outdentBlock`) and benefits from `04` existing first
  (shares the "list-kind-only" wiring pattern), though it could be built
  standalone against `02` alone if `04` isn't done yet.
- **Figma frame added 2026-08-14, resolving the design gap below**:
  `KeyboardToolbar_States` (Screens page, node-id `196:2`) — three
  labeled states built off the existing (unimplemented-in-code)
  `iOS_Editor` → `KeyboardToolbar` (node `0:713`): state A (기본, unchanged
  reference), state B (리스트 블록 포커스 — indent/outdent + keyboard-dismiss
  only), state C (같은 상태, 최상위 아이템 — outdent 비활성화). Icons are the
  user-provided Material Symbols SVGs (`format_indent_increase`,
  `format_indent_decrease`, `keyboard`), recolored to match the toolbar's
  existing icon gray. This supersedes the "no wireframe" gap `tasks/
  NO-009.md` §5 flagged — see Decisions below for what the design
  actually settled on (notably: dropping undo/redo from the list-focused
  state, and including the keyboard-dismiss button as functional, not
  just decorative).
- **No `Screen_*`/`Planning_N_*` wireframe exists for this control** —
  per `tasks/NO-009.md` §5, this is explicitly flagged as needing design
  confirmation before implementation, unlike `03`'s plain padding (which
  has enough spec detail to implement without a new frame). Resolved by
  the Figma frame above.

## Scope

- In scope:
  - A custom `UITextView.inputAccessoryView` toolbar shown only while a
    list-kind block (`bulletedListItem`/`numberedListItem`/`checklist`)
    is focused, with an indent button and an outdent button, each
    calling the same `viewModel.indentBlock(item.id)` /
    `viewModel.outdentBlock(item.id)` `04`'s hardware Tab/Shift+Tab call
    — so both trigger paths converge on identical behavior.
  - Outdent disabled/hidden when the focused item has no parent (already
    top-level) — mirrors `outdentBlock`'s own no-op guard, but surfacing
    it as a disabled control (rather than a silently-inert tap) is
    better on-screen-keyboard-affordance UX than a button that visibly
    does nothing when tapped.
  - A keyboard-dismiss button in the same toolbar (rightmost, matching
    `KeyboardToolbar_States`' state B/C) that resigns focus from the
    currently-focused block when tapped — no `inputAccessoryView`/
    keyboard-dismiss mechanism exists anywhere in the codebase today
    (confirmed by grep: zero hits for `inputAccessoryView`,
    `resignFirstResponder`, `endEditing`), so this is new behavior, not
    a rewire of something existing. Scoped narrowly: only the dismiss
    button that's part of *this* list-focused toolbar needs to work —
    building an equivalent toolbar/dismiss affordance for non-list block
    kinds (matching `KeyboardToolbar_States`' state A) is explicitly out
    of scope (see below), since that toolbar (undo/redo/bold/etc.) isn't
    implemented in code at all and isn't part of NO-009.
- Out of scope / deferred:
  - Everything already covered by `01`–`04`.
  - The general (non-list) formatting toolbar shown as
    `KeyboardToolbar_States`' state A (undo/redo/text-style/bold/code/
    quote) — that's pure Figma mockup today with no implementation and
    no task doc scoping it; not part of NO-009. Only the list-focused
    toolbar (state B/C: indent/outdent/dismiss) is built here.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `KeyboardToolbar_States` (Screens page, node `196:2`), states B & C only | `ParagraphTextField`'s `UITextView.inputAccessoryView` | State A (general formatting toolbar) is reference-only, out of scope |

## Decisions & Deviations

- **List-focused toolbar content is indent/outdent/dismiss only — no
  undo/redo.** An earlier draft of the Figma proposal kept undo/redo
  alongside indent/outdent, but the user asked to drop them so the
  list-focused state shows only the two controls actually relevant to
  it (`tasks/NO-009.md` doesn't call for undo/redo here either — this
  was an implementer-added extra in the first draft, corrected per user
  feedback, not a spec requirement).
  Overrides this brief's earlier "Decisions & Deviations: None yet" —
  the icon/layout ambiguity that section flagged is now resolved by the
  Figma frame, not left to a future implementer's judgment call.
- **Icons**: Material Symbols `format_indent_increase`/
  `format_indent_decrease`/`keyboard` (user-provided SVG source),
  recolored to the toolbar's existing muted icon gray
  (`AppTheme.Colors.Content.secondary`-equivalent) rather than the
  SVGs' original `#e3e3e3` fill, for visual consistency with the rest of
  `iOS_Editor`'s (unimplemented, state-A-only) toolbar icons. Implement
  as SF Symbols on the actual iOS build (`increase.indent`/
  `decrease.indent`/`keyboard` are real, semantically-matching SF Symbol
  names) rather than embedding the raw SVGs as image assets — matches
  every other icon in this app (`Image(systemName:)`), and SF Symbols'
  `increase.indent`/`decrease.indent` are the system-provided
  equivalents of the Material icons used for the Figma mockup.
  `keyboard` is also a valid SF Symbol name (`Image(systemName:
  "keyboard")`).
- **Outdent-disabled treatment**: 35% opacity on the button (matching
  the Figma state-C mock), not full hiding — keeps the layout stable
  (button stays in place, doesn't shift indent leftward) while still
  reading as inert.
- **Keyboard-dismiss wiring**: resign focus the same way `DetailScreen`
  already clears focus elsewhere (`focusedBlockId = nil` and/or a
  `blockIdToDefocus`-style signal, matching the existing divider-defocus
  pattern in `DetailViewModel`) rather than a raw UIKit
  `resignFirstResponder`/`endEditing` call reaching around the
  `@FocusState` binding — keeps a single source of truth for focus,
  consistent with how every other focus change in this screen already
  flows through the view model.

## Acceptance Criteria

- [ ] A `UITextView.inputAccessoryView` toolbar appears above the
      on-screen keyboard only when a list-kind block is focused, with
      indent, outdent, and keyboard-dismiss controls (no undo/redo).
- [ ] Tapping indent/outdent calls the same `viewModel.indentBlock(
      item.id)` / `viewModel.outdentBlock(item.id)` `04`'s hardware key
      handlers call.
- [ ] Outdent is shown at reduced opacity (~35%) and does not call
      `outdentBlock` when the focused item has no parent.
- [ ] Tapping the keyboard-dismiss button clears keyboard focus from the
      currently-focused block (via the view model's existing
      focus-clearing mechanism, not a direct UIKit call bypassing
      `@FocusState`), dismissing the on-screen keyboard.
- [ ] The toolbar doesn't appear for non-list-kind blocks.
- [ ] Manual on-device/Simulator verification: focusing a nested list
      item shows the toolbar with outdent at full opacity; focusing a
      top-level list item shows outdent dimmed and confirms it doesn't
      fire; tapping indent/outdent keeps keyboard focus on the same
      block afterward (no focus loss); tapping keyboard-dismiss actually
      dismisses the keyboard.

## Open Questions / Follow-ups

- None blocking — the Figma frame (`196:2`) resolves the earlier design
  gap. Icon choice, toolbar content, and the dismiss button's inclusion
  are all settled per Decisions above.
