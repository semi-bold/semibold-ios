# Feature: 05-markdown-phase4

Status: draft

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

_None yet — fill in as decisions are made during implementation._

## Acceptance Criteria

- [ ] Heading conversion (per §7.1/§7.3 syntax)
- [ ] List conversion (ordered/unordered per §7.1/§7.3)
- [ ] Checklist conversion
- [ ] Blockquote conversion
- [ ] Code block conversion
- [ ] Inline marks: bold, italic, strike, inline code, link
- [ ] Block type model matches PLANNING §8.1/§8.2 (Swift types named per
      the TS example, mapped to `contentJSON`/`markdownSource`)

## Open Questions / Follow-ups

- None yet
