# Feature: 05-markdown-phase4

Status: in-progress

## Source

- Feature spec: none (from `TASKS.md` "Markdown — Phase 4", PLANNING.md
  §18 Phase 4: Markdown 지원)
- Wireframes / planning specs: none new — extends `Screen_Detail` /
  `block-editor-phase3`'s editor with additional block types and inline
  marks
- PLANNING.md sections: §7 (지원할 Markdown / Block 요소 — §7.1 1차 지원,
  §7.3 문법 예시), §8 (블록 타입 모델 — §8.1 TypeScript 예시, §8.2 블록
  트리 구조)
- SERVICE.md sections: N/A

## Scope

- In scope:
  - Heading / list / checklist / blockquote / code block conversion
  - Inline marks: bold / italic / strike / inline code / link
- Out of scope / deferred:
  - Markdown export (`quality-phase5`, PLANNING §10.3)
  - Drag & drop, empty/error states (`quality-phase5`)

**Depends on:** `block-editor-phase3` (paragraph block editing must work
first; this extends the same editor with more block types).

## Screens & Flows

N/A — extends `Screen_Detail` from `block-editor-phase3`; no new
wireframe/flow artifact. Block type model comes from PLANNING.md §8.

## Decisions & Deviations

- **Shared block-content model** (`semibold/Models/BlockContent.swift`,
  new file): introduced `RichTextSpan` (`{ text: String }`, matching §8.1
  — `marks`/`href` deferred to AC6), `ParagraphContent`
  (`{ type: "paragraph", text: [RichTextSpan] }`), `HeadingContent`
  (`{ type: "heading", level: Int, text: [RichTextSpan] }`), and a
  `BlockContent` enum (`.paragraph`/`.heading`) with
  `encodeJSON()`/`decode(from:type:)`/`paragraphJSON(text:)`/
  `headingJSON(level:text:)` helpers for building/reading a block's
  `contentJSON`. This replaces `DetailViewModel`'s old private
  `ParagraphContent` struct (AC2/AC3's only `contentJSON` shape) — moving
  it to `Models/` makes it reusable by AC2-AC7 (list/checklist/blockquote/
  code-block shapes can be added as new `BlockContent` cases without
  touching `DetailViewModel`'s call sites). `DetailViewModel.contentJSON
  (forText:)` is now a thin private wrapper around `BlockContent
  .paragraphJSON(text:)`, kept so existing call sites (`load`,
  `insertBlock`, `mergeOrDeleteBlock`) don't need to change for this AC.
- **`DocumentBlock.displayText` / `.headingLevel`** (extension in
  `BlockContent.swift`): `displayText` decodes `contentJSON` and joins its
  `RichTextSpan`s' text — this is what `ParagraphTextField`/`BlockRow`
  show and edit, deliberately DIFFERENT from `markdownSource` once a block
  is a heading (`displayText` has no `#` prefix; `markdownSource` keeps
  it). `headingLevel` reads `contentJSON`'s `level` for `.heading` blocks
  (`nil` otherwise), used to pick the heading's typography.
- **`markdownSource` keeps the literal Markdown** (`"# Title"`,
  `"## Title"`, …) per `DocumentBlock`'s doc comment ("keeps the Markdown
  the user typed for round-tripping", §8.1). `contentJSON.text` holds only
  the text AFTER the prefix. The editor displays/edits `displayText`
  (without `#`), while `markdownSource` is rebuilt with the current
  level's `#` prefix on every subsequent edit
  (`headingMarkdownSource(level:text:)`) so it always reflects the
  heading's current content for future export (`quality-phase5`,
  PLANNING §10.3).
- **Detection & conversion** (`DetailViewModel.updateBlockText`): on every
  keystroke, if the block is currently `.paragraph` and its new full text
  matches `^#{1,3} ` (1-3 `#`s + a space, per §7.1/§7.3's `# `/`## `/`### `
  → Heading 1/2/3), the block converts to `.heading` with `level` =
  number of `#`s and `contentJSON.text` = the text after the prefix.
  4+ `#`s or a missing space after the `#`s leaves the block as a
  paragraph (matches §7.3's literal syntax — no Markdown spec supports
  `####`+ as a heading here). Conversion is persisted immediately via
  `persistBlock`, bypassing the debounce — a type change is a structural
  edit, in the same spirit as §11.2's "블록 생성/삭제/순서 변경: 즉시
  저장" for block create/delete/reorder.
- **Rendering** (`ParagraphTextField`/`BlockRow` in `DetailView.swift`):
  `ParagraphTextField` gained a `textStyle: TextStyleToken` parameter
  (default `.body`, applied to the underlying `UITextView`'s `UIFont` in
  both `makeUIView` and `updateUIView`). `BlockRow` maps `block.type`/
  `headingLevel` to `AppTheme.Typography.heading1`/`.heading2`/`.title`
  for heading levels 1/2/3. **Deviation**: `tokens.py`/`AppTheme` define
  `TYPE_HEADING1`/`TYPE_HEADING2`/`TYPE_TITLE`/`TYPE_BODY` but no
  `TYPE_HEADING3` — Heading 3 uses `AppTheme.Typography.title` (20pt
  semibold), the next size down from `heading2` in the existing scale,
  rather than inventing a new token not present in `tokens.py`. Flagged
  below for `swift-reviewer`/design follow-up if a dedicated Heading 3
  token is wanted later.
  - `BlockRow`'s `@State private var text` now initializes from
    `block.displayText` (not `block.markdownSource`), and its sync
    `.onChange` now watches `block.contentJSON` (not `markdownSource`) —
    `contentJSON` is the single source `displayText` is derived from, so
    this correctly catches both "another block's merge changed my text"
    (AC4) and "I just converted from paragraph to heading, drop the `#`
    prefix from what's displayed" (this AC).
- **Heading → paragraph reversion**: NOT implemented in this AC. §7.3's
  table only documents the Markdown → block-type direction; there's no
  spec for the reverse (e.g. Backspace-ing out all the `#`s, or
  Backspace-at-start of an empty heading). Per the brief's own guidance
  ("don't over-build"), this is left as a follow-up — currently, once a
  block becomes `.heading`, `mergeOrDeleteBlock`'s existing
  empty-block-delete / non-empty-block-merge paths still work on it (they
  operate on `markdownSource`/`displayText` regardless of type), but there
  is no "type a heading down to empty and it becomes a paragraph again"
  behavior. A future AC/brief can add this once it's needed.
- **List item content model** (`semibold/Models/BlockContent.swift`):
  added `ListItemContent` (`{ type: String, text: [RichTextSpan] }`) —
  shared by `.bulletedListItem` and `.numberedListItem` since §8.1's two
  union members have an identical `{ type, text }` shape, differing only
  in their literal `type` string (`"bulleted_list_item"` /
  `"numbered_list_item"`). `BlockContent` gained matching
  `.bulletedListItem`/`.numberedListItem` cases and
  `bulletedListItemJSON(text:)`/`numberedListItemJSON(text:)` builder
  helpers, following AC1's `headingJSON(level:text:)` pattern.
- **Applied AC1's swift-reviewer suggestion**: `BlockContent
  .decode(from:type:)`, `.text`, and `encodeJSON()`'s switches are now
  exhaustive over `BlockType` (one arm per case) rather than relying on a
  `default: .paragraph` fallback. `.paragraph`/`.heading`/
  `.bulletedListItem`/`.numberedListItem` are real cases;
  `.checklistItem`/`.blockquote`/`.codeBlock`/`.divider` (not yet modeled)
  are grouped into a single `case .checklistItem, .blockquote, .codeBlock,
  .divider:` arm that still falls back to `.paragraph` — adding any of
  those as a real case in a later AC will force the compiler to flag this
  switch.
- **Detection & conversion** (`DetailViewModel.updateBlockText`): if the
  block is currently `.paragraph` and its new full text matches `^- `
  (hyphen + space) or `^\d+\. ` (one or more digits + `. `), the block
  converts to `.bulletedListItem`/`.numberedListItem` respectively, with
  `contentJSON.text` = the text after the prefix, persisted immediately
  (same immediate-persist precedent as AC1's heading conversion).
  - **Negative cases per §7.3's literal `- item` syntax**: `"-item"` (no
    space) and `"-- item"` (a second `-` instead of item text, since after
    consuming `- ` the remaining text is `"- item"` which doesn't itself
    start with `- ` again on the *original* string's prefix check — more
    precisely, `"-- item"` doesn't match `^- ` because its 2nd character is
    `-`, not a space) do NOT convert, and stay `.paragraph`. Similarly
    `"1 item"` (space instead of `.`) and `"1.item"` (no space after `.`)
    do NOT convert. All four are covered by new
    `DetailViewModelTests` cases.
  - **`markdownSource` maintenance**: analogous to AC1's
    `headingMarkdownSource(level:text:)` — `bulletedListMarkdownSource
    (text:)` rebuilds `"- <text>"` on every edit.
    `numberedListMarkdownSource(number:text:)` rebuilds `"<n>. <text>"`,
    where `<n>` is read back from the block's *existing* `markdownSource`
    via the new `BlockContent.leadingNumber(forMarkdownSource:)` helper —
    so editing a numbered item's text keeps the number the user originally
    typed. Per the AC's explicit scope note, auto-incrementing `<n>` across
    a list's items is NOT implemented here (deferred to
    `quality-phase5`-style follow-up); literal `1. `/`42. `/etc. converting
    to a numbered-list block with that literal number is sufficient.
- **Rendering** (`BlockRow` in `DetailView.swift`): added a `listMarker`
  computed property — `"•"` for `.bulletedListItem`, `"<n>."` (from the new
  `DocumentBlock.numberedListNumber`, itself reading
  `BlockContent.leadingNumber(forMarkdownSource:)`) for
  `.numberedListItem`, `nil` (no marker) otherwise. The marker, when
  present, renders in an `HStack` to the left of the `ParagraphTextField`,
  using the same `textStyle` as the row's text and a `minWidth:
  AppTheme.Spacing.lg` (24pt) leading column so multi-digit numbers don't
  shift the text's left edge. **Deviation**: no `Screen_*`/`Planning_*`
  wireframe artifact exists for list items (checked `wireframe.py`/
  `planning.py` — only `iOS_Editor`'s generic block rows are defined, with
  no `Block_List`/list-marker layer), so the marker spacing/column width is
  a new convention using existing `AppTheme.Spacing` tokens (`sm` = 8pt gap
  between marker and text, `lg` = 24pt marker column) rather than inventing
  a new token. Flagged below for design follow-up if a dedicated list-item
  wireframe is added later.

## Acceptance Criteria

- [x] Heading conversion (per §7.1/§7.3 syntax)
- [x] List conversion (ordered/unordered per §7.1/§7.3)
- [x] Checklist conversion
- [ ] Blockquote conversion
- [ ] Code block conversion
- [ ] Inline marks: bold, italic, strike, inline code, link
- [ ] Block type model matches PLANNING §8.1/§8.2 (Swift types named per
      the TS example, mapped to `contentJSON`/`markdownSource`)

## Open Questions / Follow-ups

- Heading conversion (this AC):
  - No `TYPE_HEADING3` token exists in `tokens.py`/`AppTheme.Typography` —
    Heading 3 currently renders with `AppTheme.Typography.title` (20pt
    semibold). If design wants a visually distinct Heading 3, a
    `heading3` token should be added to `tokens.py`/`AppTheme` first.
  - Heading → paragraph reversion (e.g. deleting all the `#`s, or
    Backspace-at-start of an empty heading) is unimplemented — not
    specified by §7.3, deliberately deferred per "don't over-build". Worth
    revisiting once list/checklist/blockquote conversions (AC2-AC4) land,
    since they'll likely want the same kind of reversion behavior and a
    shared approach may emerge.
  - swift-reviewer (AC1) also noted: when AC6 adds `marks`/`href` to
    `RichTextSpan`, declare them `Optional` so existing persisted
    `contentJSON` (encoded without those keys) still decodes correctly.

- List conversion (this AC):
  - Applied the AC1 swift-reviewer suggestion: `BlockContent.decode
    (from:type:)`/`.text`/`encodeJSON()`'s switches are now exhaustive over
    `BlockType`, with `.checklistItem`/`.blockquote`/`.codeBlock`/
    `.divider` grouped into one fallback arm. AC3 (Checklist)/AC4
    (Blockquote)/AC5 (Code block) should each move their type from that
    fallback arm into a real `BlockContent` case as they're implemented —
    the compiler will flag the switch as non-exhaustive until they do.
  - List-item → paragraph reversion (Backspace-ing `- `/`<n>. ` back out,
    or Backspace-at-start of an empty list item) is unimplemented, same
    deferral rationale as AC1's heading reversion. A shared
    "structural-prefix reversion" approach for heading/list/(future
    checklist/blockquote) may be worth designing once AC3/AC4 land.
  - Numbered-list auto-increment/renumbering across a list's items (e.g.
    typing `1. `, `1. `, `1. ` on consecutive blocks auto-becoming `1.`,
    `2.`, `3.`, or renumbering after a reorder/delete) is NOT implemented —
    explicitly out of scope per this AC's instructions
    (`quality-phase5`-style nice-to-have). Each numbered list item
    currently keeps the literal number the user typed in `markdownSource`,
    read back via `BlockContent.leadingNumber(forMarkdownSource:)`.
  - No `Screen_*`/`Planning_*` wireframe artifact defines a list-item
    marker layout — `BlockRow`'s `•`/`<n>.` marker column
    (`AppTheme.Spacing.sm` gap, `AppTheme.Spacing.lg` minWidth) is a new
    convention, not traced from a wireframe. Worth a design pass once a
    dedicated list wireframe exists.
  - swift-reviewer (AC2) flagged a precedence issue for AC3: `listConversion`'s
    `^- ` check runs unconditionally, so `"- [ ] task"`/`"- [x] task"`
    (checklist syntax, §7.3) would currently match `^- ` first and
    misconvert to a bulleted list item with `displayText == "[ ] task"`.
    AC3's checklist-prefix check (`^- \[[ x]\] `) must run *before* (or be
    excluded from) the `^- ` bulleted-list check in `listConversion`/
    `updateBlockText`.
  - `DetailViewModel.swift` was already 508 lines (over SwiftLint's default
    400-line `file_length` warning threshold) before AC2; this AC's
    additions (checklist conversion + `toggleChecklistItem` + helpers) bring
    it to ~600. Still only a warning (error threshold is 1000), and the
    build has no SwiftLint errors, but AC4/AC5 (blockquote/code block) will
    add more conversion logic to the same file. Worth considering splitting
    `DetailViewModel`'s Markdown-conversion helpers
    (heading/list/checklist/blockquote/code-block detection +
    `markdownSource` builders) into a separate extension file (e.g.
    `DetailViewModel+MarkdownConversion.swift`) once AC4/AC5 land, the same
    way the conversion *tests* were just split out below.

- Checklist conversion (this AC):
  - **Checklist item content model** (`semibold/Models/BlockContent.swift`):
    added `ChecklistItemContent` (`{ type: "checklist_item", checked: Bool,
    text: [RichTextSpan] }`, §8.1) and a matching `BlockContent
    .checklistItem` case with a `checklistItemJSON(checked:text:)` builder,
    following AC1/AC2's `headingJSON`/`bulletedListItemJSON` pattern.
    `.checklistItem` is moved out of AC2's grouped fallback arm in
    `decode(from:type:)` into its own real case (falling back to
    `ChecklistItemContent(checked: false, text: [])` on malformed JSON);
    `.text`/`encodeJSON()` gained matching arms, keeping the switches
    exhaustive over `BlockType` per AC1/AC2's convention. Added
    `DocumentBlock.isChecked` (reads `contentJSON.checked`, `false` for any
    non-checklist block or malformed JSON).
  - **Precedence vs. bulleted-list conversion** (resolves the AC2
    swift-reviewer note above): `DetailViewModel.updateBlockText` now runs a
    new `checklistConversion(forTypedText:)` check *before*
    `listConversion(forTypedText:)`. If the typed text matches `^- \[ \] `
    or `^- \[x\] ` (lowercase `x` + spaces, §7.3's literal syntax), the
    `.paragraph` block converts to `.checklistItem` with `checked = false`/
    `true` respectively and `contentJSON.text` = the text after the prefix,
    persisted immediately (same immediate-persist precedent as AC1/AC2).
    Belt-and-suspenders: `listConversion`'s own `^- ` branch additionally
    guards with `checklistConversion(forTypedText: text) == nil`, so even if
    call order ever changes, `"- [ ] task"`/`"- [x] task"` still can't
    misconvert to `.bulletedListItem`.
  - **`markdownSource` maintenance**: analogous to AC1/AC2 —
    `checklistMarkdownSource(checked:text:)` rebuilds `"- [ ] <text>"` /
    `"- [x] <text>"` on every edit, keeping the literal Markdown (with
    current checked state) for round-tripping.
  - **`toggleChecklistItem(blockId:)`** (new `DetailViewModel` method): flips
    a `.checklistItem` block's `contentJSON.checked`, rebuilds
    `markdownSource` with the new `- [ ] `/`- [x] ` prefix, and persists
    immediately (a checkbox tap is a structural state change, not a text
    edit — same immediate-persist precedent as type conversions). Does
    nothing if `blockId` isn't a `.checklistItem` block.
  - **Negative cases per §7.3's literal `- [ ] `/`- [x] ` syntax**: `"- []
    task"` (no inner space) and `"- [X] task"` (uppercase `X`) do NOT match
    `checklistConversion` — per §7.3's syntax table only lowercase `x` with
    surrounding spaces (`- [ ] `/`- [x] `) is checklist syntax. Both
    therefore fall through to AC2's `^- ` bulleted-list check and become
    `.bulletedListItem` with literal `displayText == "[] task"`/`"[X] task"`
    (the `"- "` prefix is consumed, but `"[]"`/`"[X]"` is just ordinary list
    text). This is the same precedence chain, just resolving to the *other*
    branch — covered by `ChecklistConversionTests
    .nonChecklistBracketSyntaxFallsThroughToBulletedList`. **Deviation**:
    uppercase `X` is intentionally NOT treated as "checked" — if a future
    spec wants case-insensitive checklist syntax, this would need revisiting
    alongside the markdown import/export work (`quality-phase5`).
  - **Rendering** (`BlockRow` in `DetailView.swift`): `.checklistItem` blocks
    show a tappable checkbox (SF Symbol `square`/`checkmark.square`,
    `AppTheme.Colors.text2`/`.primary`) in the same leading column AC2's
    `listMarker` uses for `•`/`<n>.`, sized to `AppTheme.Spacing.lg` width
    and the row's `textStyle.lineHeight` height so it vertically centers
    against the first line of text. Tapping it calls
    `viewModel.toggleChecklistItem(blockId:)`. **Deviation**: no
    `Screen_*`/`Planning_*` wireframe artifact defines a checklist-item
    layout (checked `wireframe.py`/`planning.py` — only `iOS_Editor`'s
    generic block rows exist, same gap AC2 found for list markers), so this
    checkbox-in-leading-column placement is a new convention reusing AC2's
    column width/spacing rather than inventing new tokens. Worth a design
    pass once a dedicated checklist wireframe exists.
  - **Test file split** (new convention): `DetailViewModelTests.swift` had
    already grown past SwiftLint's default `type_body_length` (350-line
    struct body) before this AC. Rather than grow it further, the
    heading/list/checklist conversion tests were split out into their own
    topic-focused suites — `HeadingConversionTests.swift`,
    `ListConversionTests.swift`, `ChecklistConversionTests.swift` (each
    `@MainActor struct ... Tests` with its own `makeDatabaseManager()`
    helper, mirroring `DetailViewModelTests`'s pattern) — leaving
    `DetailViewModelTests.swift` covering only the `block-editor-phase3`
    create/edit/split/merge/reorder behavior it originally covered. Future
    blockquote/code-block conversion tests (AC4/AC5) should follow this same
    per-topic-file convention rather than appending to
    `DetailViewModelTests.swift`.
