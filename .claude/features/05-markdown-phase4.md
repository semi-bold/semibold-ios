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

- **Inline marks conversion (this AC)**:
  - **`RichTextSpan` gains `marks`/`href`**
    (`semibold/Models/BlockContent.swift`): added a new `RichTextMark` enum
    (`.bold`/`.italic`/`.strike`/`.inlineCode` = `"inline_code"`/`.link`,
    matching §8.1's `RichTextSpan.marks` union exactly) and two new
    `RichTextSpan` properties, `marks: [RichTextMark]?` and `href: String?`,
    both `Optional` per the AC1 swift-reviewer note (Open Questions below) —
    `contentJSON` written before this AC (`{"text": "..."}` with neither key)
    still decodes via `Codable`'s default missing-key→`nil` behavior for
    `Optional` properties, and `JSONEncoder`'s synthesized
    `encodeIfPresent`-based encoding omits `marks`/`href` entirely when
    `nil` (verified by `BlockContentTests
    .richTextSpanDecodesOldFormatJSON`/`.decodeOldFormatParagraphContentJSON`,
    which decode a literal `{"text":"Hello world"}`/
    `{"type":"paragraph","text":[{"text":"Hello world"}]}` blob with no
    `marks`/`href` keys and confirm both decode to `nil`).
  - **Chosen approach: data-model parsing, NOT WYSIWYG rendering** — per the
    brief's two offered interpretations, this AC implements the simpler one:
    `contentJSON.text`'s `[RichTextSpan]` is parsed to carry correct
    `marks`/`href` (satisfying §8.1/AC7's data model), but
    `ParagraphTextField`/`BlockRow` are UNCHANGED — no `NSAttributedString`
    rendering of bold/italic/strikethrough/monospace/links yet. Editing
    remains plain-text in a `UITextView`, with the literal `**`/`*`/`~~`/
    `` ` ``/`[]()` syntax visible while typing. Visual rendering of marks
    (bold text actually appearing bold, etc.) is explicitly deferred to
    `quality-phase5`, per the brief's own framing of this as the
    not-over-built fallback. See Open Questions below.
  - **New parsing helper**
    (`semibold/Models/BlockContent+InlineMarks.swift`, new file, following
    AC4's extension-file convention): `RichTextSpan.parse(markdownText:) ->
    [RichTextSpan]` scans `markdownText` left-to-right, trying `[text](url)`
    (link) first, then delimiter-based syntax in the order `**` (bold), `~~`
    (strike), `` ` `` (inline code), `*` (italic) — `**` before `*` so
    `**word**` isn't first read as italic. A delimiter only produces a marked
    span if BOTH an opening and a matching closing delimiter are found with
    non-empty content between them; otherwise (unterminated syntax, e.g.
    `"**bold"` with no closing `**`) those characters fall through as plain
    text — same "must match the full pattern" precedent as AC1-AC5's prefix
    conversions. Doesn't aim for full CommonMark compliance (e.g. nested
    marks like `**bold *and italic***` aren't specially recognized — the
    inner `*...*` is literal text inside the bold span) — §7.3's literal
    examples are the bar.
  - **DEVIATION — marked spans' `text` keeps its Markdown delimiters**: the
    brief's own illustrative example for AC end-to-end behavior shows
    `RichTextSpan(text:"bold", marks:["bold"])` (delimiters stripped). This
    AC instead produces `RichTextSpan(text:"**bold**", marks:["bold"])`
    (delimiters KEPT). Reason: `DocumentBlock.displayText` —
    `contentJSON.text.map(\.text).joined()` — is the exact text
    `ParagraphTextField`'s `UITextView` shows/edits, and `BlockRow` re-syncs
    its `@State text` from `displayText` on every `contentJSON` change. If
    spans stripped delimiters, `displayText` for `"**bold** text"` would
    become `"bold text"` — the view-model would silently rewrite what the
    user just typed on every keystroke, making `**`/`*`/`~~`/`` ` ``/`[]()`
    impossible to type (each keystroke immediately strips the delimiters
    again). Keeping delimiters in `text` makes `marks`/`href` correctly
    describe *which run of the literal text* is bold/italic/etc., while
    `displayText` stays exactly what the user typed — preserving the
    existing single-`UITextView` edit loop with NO changes to
    `ParagraphTextField`/`BlockRow`. A future `quality-phase5` WYSIWYG pass
    (rendering `NSAttributedString` with delimiters hidden) is the natural
    place to revisit this and strip delimiters from `text`, once
    `displayText` no longer needs to be delimiter-literal. Flagged below for
    `swift-reviewer` as the most significant deviation in this AC.
  - **Wired into all seven `BlockContent.*JSON(text:)` builders except
    `codeBlockJSON`** (`paragraphJSON`/`headingJSON`/
    `bulletedListItemJSON`/`numberedListItemJSON`/`checklistItemJSON`/
    `blockquoteJSON` in `semibold/Models/BlockContent.swift`): each now calls
    `RichTextSpan.parse(markdownText: text)` instead of wrapping `text` in a
    single unstyled `RichTextSpan`. Because `DetailViewModel.updateBlockText`
    and all of AC1-AC5's conversion paths already funnel through these
    builders with the block's current full text, inline-mark parsing
    automatically composes with every existing block-type conversion with NO
    changes to `DetailViewModel.swift`/`DetailViewModel
    +MarkdownConversion.swift` — e.g. typing `"# **bold** title"` converts to
    `.heading` (AC1) AND produces `contentJSON.text = [{"**bold**",
    marks:["bold"]}, {" title"}]` (this AC), verified end-to-end by
    `InlineMarksConversionTests
    .inlineMarksComposeWithHeadingConversion`. `codeBlockJSON` is
    deliberately NOT touched — `CodeBlockContent.code` is plain `String` per
    §8.1, not subject to inline marks.
  - **No visual rendering changes** (`ParagraphTextField.swift`/
    `DetailView.swift` UNCHANGED): see "Chosen approach" above. `BlockRow`'s
    existing `textStyle`/`textColor`/`isMonospaced` params (from AC1/AC4/AC5)
    are untouched; this AC is purely `Models/BlockContent*.swift`-side.
  - **Tests**: `BlockContentTests.swift` gained 3 new tests
    (`richTextSpanRoundTripsWithMarksAndHref`,
    `richTextSpanDecodesOldFormatJSON`,
    `decodeOldFormatParagraphContentJSON`). New
    `semiboldTests/InlineMarksTests.swift` (17 tests) covers
    `RichTextSpan.parse(markdownText:)` directly: each of the five mark
    types, mixed/adjacent/combined marks, unterminated syntax for all five
    syntaxes, and empty-delimiter edge cases (`"****"`, `"[]()"`). New
    `semiboldTests/InlineMarksConversionTests.swift` (4 tests) covers
    end-to-end `DetailViewModel.updateBlockText` behavior: bold+plain in a
    paragraph, all five marks combined in one block, inline marks composing
    with AC1's heading conversion, and plain text staying unmarked.

## Acceptance Criteria

- [x] Heading conversion (per §7.1/§7.3 syntax)
- [x] List conversion (ordered/unordered per §7.1/§7.3)
- [x] Checklist conversion
- [x] Blockquote conversion
- [x] Code block conversion
- [x] Inline marks: bold, italic, strike, inline code, link
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

- Blockquote conversion (this AC):
  - **Blockquote content model** (`semibold/Models/BlockContent.swift`):
    added `BlockquoteContent` (`{ type: "blockquote", text: RichTextSpan[]
    }`, §8.1) — a dedicated struct (not reusing `ParagraphContent`/
    `ListItemContent`) so its `type` literal (`"blockquote"`) matches its
    own `BlockType`, following `HeadingContent`/`ChecklistItemContent`'s
    precedent of one struct per case even when the shape is otherwise
    identical. Added a matching `BlockContent.blockquote` case with a
    `blockquoteJSON(text:)` builder. `.blockquote` is moved out of AC2's
    grouped fallback arm in `decode(from:type:)`/`.text`/`encodeJSON()`
    into its own real case (falling back to `BlockquoteContent(text: [])`
    on malformed JSON); the remaining fallback arm is now `.codeBlock,
    .divider` only, keeping the switches exhaustive over `BlockType` per
    AC1-AC3's convention. AC5 (code block) should move `.codeBlock` out of
    that arm next.
  - **Detection & conversion** (`DetailViewModel.updateBlockText`): a new
    `blockquoteConversion(forTypedText:)` check runs after the list check
    (no precedence conflict — `> ` doesn't overlap with `#`/`-`/`<n>. `/
    `- [ ] `/`- [x] `'s leading characters). If the typed text matches
    `^> ` (greater-than + space, §7.1/§7.3's `> quote` syntax), the
    `.paragraph` block converts to `.blockquote` with `contentJSON.text` =
    the text after the prefix, persisted immediately (same
    immediate-persist precedent as AC1-AC3).
  - **`markdownSource` maintenance**: analogous to AC1-AC3 —
    `blockquoteMarkdownSource(text:)` rebuilds `"> <text>"` on every edit,
    keeping the literal Markdown for round-tripping.
  - **Negative cases per §7.3's literal `> quote` syntax**: `">quote"` (no
    space) and `">> quote"` (2nd character is `>`, not a space) do NOT
    convert and stay `.paragraph` — same precedent as AC2's `"-item"`/
    `"-- item"` not matching `"- "`. Both covered by new
    `BlockquoteConversionTests` cases, plus a precedence test confirming
    `"# Title"`/`"- item"`/`"1. item"`/`"- [ ] task"` never convert to
    `.blockquote`.
  - **Rendering** (`BlockRow`/`ParagraphTextField` in `DetailView.swift`/
    `ParagraphTextField.swift`): `.blockquote` blocks show a vertical rule
    (`AppTheme.Colors.border`, `AppTheme.Spacing.xs` wide) in the same
    leading column AC2/AC3's `listMarker`/checkbox use, sized to
    `AppTheme.Spacing.lg` minWidth for the same left-edge alignment. The
    quote's text itself is dimmed to `AppTheme.Colors.text2` (vs. the
    default `.text1`) to read visually as a quote. `ParagraphTextField`
    gained a `textColor: Color` parameter (default `.text1`, applied to the
    underlying `UITextView`'s `textColor` in both `makeUIView` and
    `updateUIView`), mirroring AC1's `textStyle` parameter precedent.
    **Deviation**: no `Screen_*`/`Planning_*` wireframe artifact defines a
    blockquote layout (checked `wireframe.py`/`planning.py` — only
    `iOS_Editor`'s generic block rows exist, same gap AC2/AC3 found), so
    this leading vertical-rule + dimmed-text treatment is a new convention
    reusing AC2's column width/spacing tokens rather than inventing new
    ones. Worth a design pass once a dedicated blockquote wireframe exists.
  - **`DetailViewModel` file split** (per swift-reviewer/AC3's
    suggested-not-blocking follow-up): extracted all Markdown
    prefix-detection/`markdownSource`-builder helpers (heading/list/
    checklist/blockquote — `headingConversion`/`listConversion`/
    `checklistConversion`/`blockquoteConversion` and their `*MarkdownSource`
    builders/private content structs) into a new
    `semibold/ViewModels/DetailViewModel+MarkdownConversion.swift`
    extension. This dropped `DetailViewModel.swift` from ~600 lines to 436
    (still slightly over SwiftLint's 400-line `file_length` warning
    threshold, but the `type_body_length` warning the class body previously
    had is now resolved). The extracted helpers changed from `private
    static` to internal `static` (Swift's `private` is file-scoped, so
    `updateBlockText` in the main file couldn't call file-scoped-private
    members in the extension file) — still implementation details of
    `DetailViewModel`, just not enforced at the file level. AC5 (code block)
    should add its conversion helpers to this new extension file rather than
    back to `DetailViewModel.swift`.
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
    **Resolved in AC4**: split into
    `DetailViewModel+MarkdownConversion.swift`, bringing `DetailViewModel
    .swift` down to 436 lines. Still a `file_length` warning (not an error)
    — AC5 (code block) should keep adding its conversion helpers to the new
    extension file rather than `DetailViewModel.swift` to avoid growing it
    further.

- Blockquote conversion (this AC):
  - `BlockContent.decode(from:type:)`'s switch is now complexity 14
    (SwiftLint's `cyclomatic_complexity` warning threshold is 10; this was
    already a pre-existing warning at complexity 12 before this AC).
    `updateBlockText` is now complexity 12 / 70 lines (also a pre-existing
    `function_body_length`/`cyclomatic_complexity` warning, previously 12 /
    58 lines). Both are warnings only (not errors) and follow the exhaustive
    `BlockType`-switch / per-type-branch conventions AC1-AC3 established —
    AC5 (code block) will add one more arm/branch to each. If these warnings
    become a priority, the natural follow-up is extracting `BlockContent
    .decode`'s per-type branches into smaller helper functions, and/or
    restructuring `updateBlockText`'s conversion checks into a small
    ordered-list-of-conversions loop — neither attempted here to avoid
    scope creep on this AC.
  - Blockquote → paragraph reversion (Backspace-ing the `> ` back out, or
    Backspace-at-start of an empty blockquote) is unimplemented, same
    deferral rationale as AC1/AC2's heading/list-item reversion follow-ups.

- Code block conversion (this AC):
  - **Single-block fence conversion, not multi-line textarea editing**: per
    the brief's own framing, option (a) was chosen — typing a complete
    ` ``` `/` ```<lang> ` fence prefix on a `.paragraph` block converts THAT
    block to `.codeBlock` immediately, the same "convert on prefix,
    persist immediately" precedent as AC1-AC4. The closing ` ``` ` fence is
    NOT required for the conversion to happen — `block-editor-phase3`'s
    Enter key creates new blocks rather than inserting newlines within one
    block, so there is no in-block mechanism to type a second line and a
    closing fence within the same block yet. `markdownSource` is rebuilt
    with a closing fence (see below) purely for round-tripping, not because
    the user typed one.
  - **Code-block content model** (`semibold/Models/BlockContent.swift`):
    added `CodeBlockContent` (`{ type: "code_block", language: String?,
    code: String }`, §8.1 — field names match the TS example exactly,
    `language` optional/nullable) and a matching `BlockContent.codeBlock`
    case with a `codeBlockJSON(language:code:)` builder. `.codeBlock` is
    moved out of AC2's grouped fallback arm in `decode(from:type:)` into
    its own real case (falling back to `CodeBlockContent(language: nil,
    code: "")` on malformed JSON); `encodeJSON()` gained a matching arm.
    The remaining fallback arm in `decode(from:type:)` is now `.divider`
    only — left as a single-case fallback (falling back to `.paragraph`)
    rather than given its own `BlockContent.divider` case, since `.divider`
    has no content fields at all per §8.1 (`{ type: "divider" }`) and isn't
    in this AC's scope; a future divider AC can add a real case then.
  - **`.text`/`displayText` for `.codeBlock`**: rather than adding a
    separate `displayText` branch, `BlockContent.text` wraps a code block's
    `code` (plain `String`, not `[RichTextSpan]` per §8.1) in a single
    unstyled `RichTextSpan`. `DocumentBlock.displayText`'s existing
    `.text.map(\.text).joined()` then returns `code` unchanged, so
    `.codeBlock` needs no special case in `displayText` itself — keeps the
    accessor uniform across all seven cases. Added
    `DocumentBlock.codeLanguage` (reads `contentJSON.language`, `nil` for
    non-code blocks or a fence with no language) for `BlockRow`'s language
    label.
  - **Detection & conversion**
    (`DetailViewModel+MarkdownConversion.swift`'s new
    `codeBlockConversion(forTypedText:)`, called from `updateBlockText`
    after the blockquote check): if the typed text starts with exactly
    three backticks (` ``` `), the `.paragraph` block converts to
    `.codeBlock`. The `language` is the run of non-whitespace characters
    immediately after the fence (e.g. `"swift"` for ` ```swift`), or `nil`
    if the fence is immediately followed by whitespace or end-of-string
    (a bare ` ``` `). Any text after the language (minus one separating
    space, if present) becomes the code block's initial `code` — e.g.
    ` ```swift let x = 1` → `language: "swift"`, `code: "let x = 1"`.
    Persisted immediately, same precedent as AC1-AC4. No precedence
    conflict with `#`/`-`/`<n>. `/`- [ ] `/`> ` — backtick doesn't overlap
    with any of those leading characters.
  - **Negative cases per §7.3's literal ` ```lang ` syntax**: `` ` `` (one
    backtick) and `` `` `` (two backticks) do NOT match the three-backtick
    fence prefix and stay `.paragraph` — single/double backtick is inline-
    code syntax (`` `code` ``, AC6 scope), not a code-fence. Both covered by
    new `CodeBlockConversionTests` cases, plus a precedence test confirming
    `"# Title"`/`"- item"`/`"1. item"`/`"- [ ] task"`/`"> quote"` never
    convert to `.codeBlock`.
  - **`markdownSource` maintenance**: new
    `codeBlockMarkdownSource(language:code:)` rebuilds
    ` ```<language>\n<code>\n``` ` (closing fence included) on every edit —
    unlike AC1-AC4's single-line builders, this is multi-line, matching the
    brief's explicit guidance. Editing a code block's `code` (the text
    `ParagraphTextField` reports back, i.e. `displayText` without the
    fence) keeps the block's existing `language` and rebuilds both
    `contentJSON` and `markdownSource` via this helper.
  - **Rendering** (`BlockRow` in `DetailView.swift`,
    `ParagraphTextField.swift`): `.codeBlock` blocks render their code in a
    monospaced font (`ParagraphTextField` gained an `isMonospaced: Bool`
    parameter, using `UIFont.monospacedSystemFont(ofSize:weight:)` at the
    row's `textStyle` size/weight — `.body`, since no dedicated code-block
    typography token exists) on a distinguishing background
    (`AppTheme.Colors.surface2`, the next surface layer up from
    `.background`, applied to the row's content `VStack` so the divider
    below stays the normal background color). If the fence had a language,
    it's shown as a small `AppTheme.Typography.caption` /
    `AppTheme.Colors.text2` label above the code. **Deviation**: no
    `Screen_*`/`Planning_*` wireframe artifact defines a code-block layout
    (checked `wireframe.py`/`planning.py` — only `iOS_Editor`'s generic
    block rows exist, same gap AC2-AC4 found), and `tokens.py` has no
    font-family/monospace token at all (every typography token is
    size/weight/line-height only) — `surface2` background + system
    monospaced font + existing `caption`/`text2` for the language label are
    new conventions reusing existing `AppTheme` tokens rather than inventing
    new ones. Worth a design pass once a dedicated code-block wireframe
    exists.

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

- Code block conversion (this AC):
  - **Multi-line code editing within one block is NOT implemented** —
    `ParagraphTextField`'s `UITextView` still treats Return as "create a
    new block" (`block-editor-phase3`'s Enter-to-create), so a `.codeBlock`
    block's `code` can only ever be a single line in this editor today.
    Typing a closing ` ``` ` fence on its own "line" isn't possible without
    a newline, so it's neither detected nor required — `markdownSource`'s
    closing fence is synthetic (added by `codeBlockMarkdownSource` for
    round-tripping only). A future AC that wants real multi-line code
    blocks would need either: (a) a textarea-style block that accepts
    literal newlines (diverging from the current one-block-per-line model),
    or (b) representing a code block as multiple `DocumentBlock` rows under
    a shared `parentId` (§8.2's block-tree structure already supports
    nesting). Neither is attempted here per the brief's "don't over-build"
    guidance.
  - **Code block → paragraph reversion** (Backspace-ing the fence back out,
    or Backspace-at-start of an empty code block) is unimplemented, same
    deferral rationale as AC1-AC4's heading/list/checklist/blockquote
    reversion follow-ups.
  - **4+ backtick fences** (e.g. ` ```` `, GFM's "fences can be 4+
    backticks if the code itself contains a 3-backtick run") are not
    specially handled — `codeBlockConversion(forTypedText:)` only checks
    `hasPrefix("```")`, so ` ```` ` would be detected as a 3-backtick fence
    with `` ` `` treated as the start of its "language" (a single stray
    backtick character). §7.3 doesn't specify 4+-backtick fences, and this
    is an unlikely thing to type by hand, so it's left as-is — worth
    revisiting only if markdown import/export (`quality-phase5`) needs to
    round-trip such fences.
  - **Inline code** (`` `code` ``, single backticks, §7.3) is explicitly
    AC6 (inline marks) scope, not this AC — `codeBlockConversion` only
    matches three or more leading backticks, so `` `code` ``/`` ``code`` ``
    correctly fall through to stay `.paragraph` here (covered by
    `CodeBlockConversionTests.oneBacktickDoesNotConvert`/
    `.twoBackticksDoesNotConvert`).

- Inline marks conversion (this AC):
  - **Visual rendering of marks is NOT implemented** — `ParagraphTextField`/
    `BlockRow` are plain-text and unchanged; bold/italic/strikethrough/
    inline-code/link spans don't yet appear visually distinct while editing
    or viewing a block. `contentJSON.text` correctly carries `marks`/`href`
    for future use (export, a read-only rendered view, etc.), but a
    `quality-phase5`-style pass is needed to render `NSAttributedString`
    (bold/italic font traits via `UIFontDescriptor.SymbolicTraits`,
    `NSAttributedString.Key.strikethroughStyle`, a monospace font for
    `.inlineCode` spans, and `NSAttributedString.Key.link` + underline for
    `href` spans with tap-to-open behavior).
  - **Marked spans' `text` retains Markdown delimiters** (`"**bold**"`, not
    `"bold"`) — see the DEVIATION note in Decisions & Deviations above. If a
    future WYSIWYG pass wants "clean" text in `RichTextSpan.text` (delimiters
    hidden, marks rendered), `displayText`'s relationship to `contentJSON`
    needs to be redesigned at the same time (e.g. `displayText` sourced from
    `markdownSource` minus structural prefix, rather than from
    `contentJSON.text` joined) — these two changes are coupled and should
    land together.
  - **Nested/overlapping marks are not specially handled** (e.g. `**bold
    *and italic***`, `` `code with **bold** inside` ``) — `RichTextSpan.parse`
    tries one delimiter type at a time and doesn't recurse into matched
    spans, so any inner delimiters are literal text within the outer marked
    span's `text`. §7.3 doesn't specify nested-mark syntax, so this is left
    as-is; full CommonMark-style nesting would need a recursive/precedence-
    aware parser if a future spec requires it.
  - **Link-tap-to-open behavior** is unimplemented (follows from "visual
    rendering not implemented" above) — `href` is captured in `contentJSON`
    but nothing in the UI currently makes a link span tappable/openable. Part
    of the same `quality-phase5` rendering pass.
  - **`*` vs `_` for italic/bold, and other CommonMark delimiter variants**
    (e.g. `_italic_`, `__bold__`) are not recognized — §7.3's literal syntax
    table only shows `**`/`*`/`~~`/`` ` ``/`[]()`, so only those are
    implemented. Worth revisiting if markdown import (`quality-phase5`) needs
    to round-trip documents using underscore-style emphasis.
