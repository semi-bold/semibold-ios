# Feature: 06-quality-phase5

Status: in-progress

## Source

- Feature spec: none (from `TASKS.md` "Quality pass — Phase 5",
  PLANNING.md §18 Phase 5: iOS / macOS 공통 품질 개선)
- Wireframes / planning specs:
  - `Planning_5_MacOSMainFlow` (`../sketch-autokit/screens/planning.py`)
    for the macOS shortcut/menu behavior
- PLANNING.md sections: §10.3 (Markdown Export 흐름), §12 (iOS / macOS
  공통 설계 — §12.2 플랫폼별 UI, §12.3 공통 인터랙션), §13.2 (macOS 단축키
  예시), §15 (에러 및 빈 상태 — §15.1 빈 상태, §15.2 에러 상태)
- SERVICE.md sections: N/A

## Scope

- In scope:
  - macOS keyboard shortcuts, iOS slash-command bottom sheet (§12.2,
    §13.2)
  - Drag & drop reordering (§12.3)
  - Empty/error states (§15.1, §15.2)
  - Markdown export (§10.3)
- Out of scope / deferred:
  - None — this is the final planned phase per PLANNING §18

**Depends on:** `block-editor-phase3` and `markdown-phase4` (export and
drag & drop operate on the block editor and block types built there).

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| Planning_5_MacOSMainFlow | TBD | macOS menu/shortcut behavior |

Empty/error states and markdown export apply across `HomeView` and the
detail/editor view from earlier phases — no new dedicated screen.

## Decisions & Deviations

### macOS keyboard shortcuts (§13.2)

- **App structure.** `semibold` is currently a single iOS-platform target
  (`project.yml` has no macOS target). `.commands`/`.keyboardShortcut()`
  still compile and are exercised under "My Mac (Designed for iPad)"/Mac
  Catalyst-style destinations, so the shortcuts below are wired at the
  SwiftUI level without adding a macOS target or `#if os(macOS)` guards —
  consistent with "no full 3-column macOS layout in this AC" per the
  brief.
- **Cmd+N / Cmd+Shift+N** ("새 문서" / "새 폴더"): implemented via
  `CommandGroup(replacing: .newItem)` in `SemiboldApp.swift`. Since
  `HomeView`'s new-document/new-folder sheets are presented from
  view-local `@State`, added a tiny app-level `@Observable
  AppCommandCenter` (two request counters) injected via `.environment` —
  `SemiboldApp`'s menu commands bump a counter, `HomeView` observes it via
  `.onChange` and opens the same sheet a "+" tap would. No new
  app-wide view model beyond this minimal trigger.
- **Cmd+Option+1/2/3** (Heading 1/2/3, §13.2 / `Planning_5_MacOSMainFlow`
  callout ⑤'s "블록 타입 변환" via keyboard instead of a right-click menu):
  `DetailViewModel.convertBlockToHeading(_:level:)` converts whichever
  block currently has focus (`DetailView`'s existing `@FocusState
  focusedBlockId`) to a `.heading` at that level, keeping its text —
  reusing AC1's `headingMarkdownSource`/`BlockContent.headingJSON` helpers.
  Wired via hidden, zero-size `Button`s with `.keyboardShortcut(_:
  modifiers: [.command, .option])` in `DetailView`, since
  `ParagraphTextField` (a `UITextView` wrapper) doesn't surface this key
  combo to SwiftUI directly.
- **Cmd+B / Cmd+I / Cmd+K** (Bold/Italic/Link, §13.2): **scoped down from
  selection-based formatting**. `ParagraphTextField` doesn't expose
  `UITextView.selectedRange` to SwiftUI, so these toggle Markdown
  delimiters (`**…**`, `*…*`, `[…]()`) around the **focused block's whole
  text** rather than a text selection — pressing the shortcut again
  removes the wrapper (on/off toggle). An empty block does nothing for any
  of the three. This mirrors AC1-AC5's existing "whole-block Markdown
  conversion" precedent (`DetailViewModel+MarkdownConversion.swift`) and
  keeps the shortcuts usable without a `ParagraphTextField`/UITextView
  rework. Selection-scoped formatting is a natural follow-up once
  `ParagraphTextField` exposes the selection range.
  - New view-model logic lives in
    `DetailViewModel+KeyboardShortcuts.swift`, following the existing
    `+MarkdownConversion` extension-file split. `blocks`,
    `pendingSaveTasks`, and `documentBlockRepository` were loosened from
    `private` to `internal` (module-only) on `DetailViewModel` so this
    sibling file can apply/persist the same edits `updateBlockText` does —
    documented inline at each property.
- **`Planning_5_MacOSMainFlow`**: the full 3-column Sidebar/document-list/
  Editor layout (callouts ①-④) remains out of scope for this AC, per the
  brief — only callout ⑤'s "block type conversion without needing to know
  a keyboard shortcut" goal is addressed indirectly, via the
  Cmd+Option+1/2/3 shortcuts themselves (not a right-click menu).

### iOS Slash Command bottom sheet (§12.2/§13.1)

- **Trigger detection.** `DetailViewModel.updateBlockText` now checks
  `Self.isSlashCommandTrigger(forTypedText:currentType:)` first, before
  AC1-AC5's other prefix conversions: if the block is currently a
  `.paragraph` and its text is now exactly `"/"` (i.e. the user typed `/`
  as the very first character of an empty block), the `/` is consumed —
  cleared back to an empty paragraph and persisted immediately, like the
  other structural conversions (PLANNING §11.2 "블록 생성/삭제/순서 변경:
  즉시 저장") — and `slashCommandBlockId` is set so `DetailView` presents the
  sheet. `/` typed mid-sentence (`"1/2"`) or in a non-paragraph block
  doesn't trigger it, mirroring how `headingConversion`/etc. only fire on a
  complete leading prefix.
- **Sheet UI.** New `SlashCommandSheet` (`Views/SlashCommandSheet.swift`)
  lists `SlashCommandOption`'s 9 cases (Heading 1/2/3, Bulleted list,
  Numbered list, Checklist, Blockquote, Code block, Divider — everything
  except plain paragraph) as a `List` of icon+label rows, presented via
  `.sheet(isPresented:)` at `.medium`/`.large` detents. **No
  `Screen_*`/`Planning_N_*Flow` artboard defines a "slash command menu"
  component** (checked `wireframe.py`/`planning.py`/`atoms.py` — only
  prose references to "Slash Command" in `planning.py`'s callout text, no
  layout) — per CLAUDE.md §0 step 3, this is documented here rather than
  invented as a new wireframe. The row layout (leading SF Symbol icon,
  label, row divider) follows `atoms.py`'s `doc_row` list-row language,
  styled with `AppTheme` tokens (`Colors.background/text1/text2`,
  `Spacing.md/lg`, `Typography.body`).
- **Conversion.** Picking an option calls
  `DetailViewModel.convertBlock(_:toSlashCommandOption:)`
  (`ViewModels/DetailViewModel+SlashCommand.swift`, following the
  `+MarkdownConversion`/`+KeyboardShortcuts` extension-file split) — sets
  the block's type and an **empty** `contentJSON`/`markdownSource` via the
  existing `*JSON`/`*MarkdownSource` helpers (`headingJSON(level:text:"")`,
  `bulletedListItemJSON(text:"")`, `checklistItemJSON(checked:false,
  text:"")`, `blockquoteJSON(text:"")`, `codeBlockJSON(language:nil,
  code:"")`, `dividerJSON()`), persists immediately, and dismisses the
  sheet. The block stays focused so the user can keep typing in the new
  type. Heading 1/2/3 map to `.heading` at level 1/2/3, consistent with
  Cmd+Option+1/2/3 (AC1).
- **Divider included.** Brief 05's Open Question (`.divider`/`dividerJSON()`
  dead code, no rendering) is resolved here: `BlockRow` now branches on a
  new `isDivider` check and renders a `.divider` block as a horizontal-rule
  row (`Rectangle` filled with `AppTheme.Colors.border`, `Spacing.lg`
  vertical padding) with no `ParagraphTextField` — a divider has no text
  content (§8.1 `{ type: "divider" }`), so it isn't editable. This was a
  low-effort addition once the slash-command menu existed, so Divider is
  included as a full menu option rather than excluded.
- **Sheet dismiss without picking.** Swiping the sheet away calls
  `dismissSlashCommand()` (via the `.sheet(isPresented:)` binding's setter),
  leaving the block as the empty paragraph the `/`-clearing step already
  produced — no extra "undo" path needed.

## Acceptance Criteria

- [x] macOS keyboard shortcuts implemented per PLANNING §13.2 and
      `Planning_5_MacOSMainFlow`
- [x] iOS slash-command bottom sheet for inserting block types
- [ ] Drag & drop block reordering (§12.3)
- [ ] Empty states implemented per §15.1
- [ ] Error states implemented per §15.2
- [ ] Markdown export implemented per §10.3

## Open Questions / Follow-ups

- None yet
