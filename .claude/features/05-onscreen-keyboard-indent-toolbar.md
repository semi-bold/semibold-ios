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
- **No `Screen_*`/`Planning_N_*` wireframe exists for this control** —
  per `tasks/NO-009.md` §5, this is explicitly flagged as needing design
  confirmation before implementation, unlike `03`'s plain padding (which
  has enough spec detail to implement without a new frame).

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
- Out of scope / deferred:
  - Everything already covered by `01`–`04`.
  - Any icon/visual design beyond what this brief's Open Question below
    resolves.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| **None yet — blocked, see Open Questions** | `ParagraphTextField`'s `UITextView.inputAccessoryView` | No `Screen_*`/`Planning_N_*` frame covers this control |

## Decisions & Deviations

- None yet — implementation specifics (icon choice, toolbar layout,
  whether it's a full-width bar or a compact leading-aligned cluster)
  are deferred to the Open Question below rather than guessed at, since
  `tasks/NO-009.md` §5 explicitly calls this out as needing confirmation
  before work starts (unlike `03`'s indent-padding, which had enough
  spec detail to proceed without new design).

## Acceptance Criteria

- [ ] A `UITextView.inputAccessoryView` toolbar appears above the
      on-screen keyboard only when a list-kind block is focused, with
      indent and outdent controls.
- [ ] Tapping indent/outdent calls the same `viewModel.indentBlock(
      item.id)` / `viewModel.outdentBlock(item.id)` `04`'s hardware key
      handlers call.
- [ ] Outdent is disabled (or hidden) when the focused item has no
      parent.
- [ ] The toolbar doesn't appear for non-list-kind blocks.
- [ ] Manual on-device/Simulator verification: focusing a nested list
      item shows the toolbar with outdent enabled; focusing a top-level
      list item shows it with outdent disabled; tapping either button
      keeps keyboard focus on the same block afterward (no focus loss).

## Open Questions / Follow-ups

- **Blocking**: this control's exact visual design (icon choice — e.g.
  SF Symbols `increase.indent`/`decrease.indent` vs. something custom —
  toolbar layout/placement, whether it's always full-width or a compact
  cluster, light/dark appearance) has no Figma frame yet
  (`tasks/NO-009.md` §5 flags this explicitly). Per CLAUDE.md §0's "if a
  request conflicts with these docs, or no matching frame/spec exists
  yet, say so explicitly rather than improvising silently," this brief
  should not be implemented until either (a) a matching Figma frame is
  added, or (b) the user explicitly signs off on an implementer-proposed
  design (e.g. plain SF Symbols in a standard `UIToolbar`) as a stand-in.
