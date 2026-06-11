# Feature: 06-quality-phase5

Status: draft

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

_None yet — fill in as decisions are made during implementation._

## Acceptance Criteria

- [ ] macOS keyboard shortcuts implemented per PLANNING §13.2 and
      `Planning_5_MacOSMainFlow`
- [ ] iOS slash-command bottom sheet for inserting block types
- [ ] Drag & drop block reordering (§12.3)
- [ ] Empty states implemented per §15.1
- [ ] Error states implemented per §15.2
- [ ] Markdown export implemented per §10.3

## Open Questions / Follow-ups

- None yet
