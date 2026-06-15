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

## Acceptance Criteria

- [x] Heading conversion (per §7.1/§7.3 syntax)
- [ ] List conversion (ordered/unordered per §7.1/§7.3)
- [ ] Checklist conversion
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
  - swift-reviewer (AC1) suggested making `BlockContent.decode(from:type:)`
    /`.text`/`encodeJSON()`'s switches exhaustive (one arm per `BlockType`)
    instead of a `default: .paragraph` fallback, so each of AC2-AC5's new
    `BlockContent` cases forces a compiler error at every switch site
    instead of silently falling back. Worth applying when AC2 (List
    conversion) adds its first new case, rather than reworking all switches
    at once now.
  - swift-reviewer (AC1) also noted: when AC6 adds `marks`/`href` to
    `RichTextSpan`, declare them `Optional` so existing persisted
    `contentJSON` (encoded without those keys) still decodes correctly.
