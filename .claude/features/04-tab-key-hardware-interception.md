# Feature: 04-tab-key-hardware-interception

## Source

- `tasks/NO-009.md` §2.1 "물리 Tab/Shift+Tab 키(외장 키보드 연결 시)...
  함께 지원한다", §3.3 (existing `shouldChangeTextIn` interception can't
  catch Shift+Tab since it usually inserts no character — needs a
  separate hardware key-event mechanism, `UIKeyCommand`/`pressesBegan`).
- Depends on `02-indent-outdent-viewmodel` — this brief only wires a
  trigger to `indentBlock`/`outdentBlock`, which must already exist.
- No `Screen_*`/`Planning_N_*` wireframe — hardware key handling has no
  visual surface.

## Scope

- In scope:
  - `ParagraphTextField` (`Views/Components/Shared/ParagraphTextField
    .swift`) gains Tab/Shift+Tab handling for its wrapped `UITextView`,
    via `UIKeyCommand` (registered on the `UITextView`/its
    `Coordinator`) rather than `UITextViewDelegate.shouldChangeTextIn`
    (`tasks/NO-009.md` §3.3 — the existing mechanism `onEnter`/
    `onBackspaceAtStart` use only fires on an actual text-change event,
    which Shift+Tab typically doesn't produce).
  - Two new callbacks on `ParagraphTextField`, parallel to the existing
    `onEnter`/`onBackspaceAtStart`: `onIndent: () -> Void` and
    `onOutdent: () -> Void`, wired at each list-kind block's call site
    (`BulletedListBlockView`/`NumberedListBlockView`/`ChecklistBlockView`
    `.chrome(...)` factories, then `BlockRowChrome`, then
    `DetailScreen.blockRow(for:content:)`) to `viewModel.indentBlock(
    item.id)` / `viewModel.outdentBlock(item.id)` — the exact same
    `indentBlock`/`outdentBlock` calls `05`'s toolbar button will also
    make, so both triggers converge on one implementation.
  - Only registered/active for list-kind blocks — Tab on a non-list
    block (paragraph, heading, etc.) does nothing special (falls through
    to whatever `UITextView`'s default Tab behavior is, i.e. inserting a
    tab character, unchanged from today), since indent/outdent is
    list-only (`tasks/NO-009.md` §2.1).
- Out of scope / deferred:
  - The on-screen keyboard toolbar button — `05` (needs design
    confirmation first, `tasks/NO-009.md` §5).
  - Any depth cap — none exists in `02`'s `indentBlock`/`outdentBlock`,
    and this brief doesn't add one at the trigger layer either.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| — (hardware input handling only) | `ParagraphTextField`, `BlockRowChrome`, list-kind `*BlockView.chrome(...)` factories | No visual change; only reachable with an external keyboard attached |

## Decisions & Deviations

- **`onIndent`/`onOutdent` are optional, defaulted to `nil`** on
  `ParagraphTextField` (not required parameters) — every non-list block
  factory keeps constructing `ParagraphTextField`/`BlockRowChrome`
  without passing them, so this brief doesn't force a signature change
  on kinds that will never use it. Mirrors how `BlockRowChrome`'s own
  `leadingContent`/`isDividerRow` are defaulted, keeping the "same
  concrete type across all factories" property intact (`BlockRowChrome`'s
  doc comment) — these are still plain closure parameters (not
  `View`-typed), so they don't reintroduce the generic-type problem that
  doc comment warns about.
- **`UIKeyCommand` registered via `UITextView.subclass` override or
  `keyCommands` on the coordinator/text view** — implementer's call on
  the exact mechanism (`UITextView` subclass overriding
  `keyCommands`/`pressesBegan(_:with:)` vs. a `UIKeyCommand` array
  assigned some other way); whichever is more consistent with
  `ParagraphTextField`'s existing `UIViewRepresentable`/`Coordinator`
  structure. Must not require a hardware keyboard to *build* — only to
  *trigger* (an iOS Simulator with "Connect Hardware Keyboard" enabled,
  or a physical external keyboard, needed to manually verify Tab/
  Shift+Tab; automated tests instead call `onIndent`/`onOutdent`
  directly / call `indentBlock`/`outdentBlock` on the view model, since
  simulating a hardware key event in `XCTest`/Swift Testing isn't
  practical here).

## Acceptance Criteria

- [ ] `ParagraphTextField` accepts optional `onIndent: (() -> Void)? =
      nil` / `onOutdent: (() -> Void)? = nil`, and, when non-nil,
      intercepts a hardware Tab press to call `onIndent` and Shift+Tab to
      call `onOutdent`, consuming the key event (not inserting a tab
      character) whenever a handler is provided.
- [ ] Blocks without handlers (every non-list kind) are unaffected — Tab
      behaves exactly as before (whatever `UITextView`'s default is).
- [ ] `BulletedListBlockView`/`NumberedListBlockView`/`ChecklistBlockView`
      `.chrome(...)` wire `onIndent`/`onOutdent` through `BlockRowChrome`
      down to `ParagraphTextField`, and `DetailScreen.blockRow(for:
      content:)` supplies closures calling `viewModel.indentBlock(
      item.id)` / `viewModel.outdentBlock(item.id)` for those three
      kinds only.
- [ ] Manual verification with a hardware keyboard attached (Simulator's
      "Connect Hardware Keyboard" or a physical external keyboard):
      pressing Tab on a focused list item indents it; Shift+Tab outdents
      it; both keep keyboard focus on the same block afterward (no focus
      loss — consistent with the identity-preservation fix already in
      `BlockRowChrome`).
- [ ] Unit tests at the `onIndent`/`onOutdent` closure level (calling
      them directly, not simulating real key events) confirm they invoke
      `indentBlock`/`outdentBlock` with the correct block id.

## Open Questions / Follow-ups

- None blocking.
