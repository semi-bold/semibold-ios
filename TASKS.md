# Tasks

Working task list for `semibold-ios`. Update as work progresses — check
items off, add new ones under the relevant phase. Phase numbers refer to
`../sketch-autokit/docs/PLANNING.md` §18.

## Done

- [x] `CLAUDE.md` — source-of-truth pointers, wireframe/planning-spec
      mapping, tech stack, coding conventions, README constraints
- [x] `README.md` — build/setup instructions
- [x] `.claude/agents/feature-implementer.md` — per-Acceptance-Criteria-item
      implementation agent (parallelizable)
- [x] `.claude/agents/swift-reviewer.md` — read-only convention/design
      review agent
- [x] XcodeGen setup (`project.yml`) — iOS 17 target, GRDB.swift,
      SwiftLint build plugin
- [x] Initial SwiftUI app skeleton (`SemiboldApp`, `ContentView`) —
      builds and runs on iOS Simulator
- [x] `.claude/features/` convention — `TEMPLATE.md` for per-feature
      briefs (scope, decisions/deviations, acceptance criteria), referenced
      by `CLAUDE.md` §0 and read first by `feature-implementer`/
      `swift-reviewer` so work is reproducible across machines/sessions

## Next

Each phase below has a corresponding feature brief in
`.claude/features/` with full scope, screen/flow mappings, and acceptance
criteria — read the brief before starting that phase.

- [ ] **01 — Project structure & theming** — `semibold/` folder layout +
      `AppTheme` design tokens →
      `.claude/features/01-project-structure-theming.md`
- [ ] **02 — Local DB — Phase 1** — GRDB `DatabaseManager`/`DatabaseMigrator`,
      `folders`/`documents`/`document_blocks` tables, repository layer →
      `.claude/features/02-local-db-phase1.md`
- [ ] **03 — UI — Phase 2** — `Screen_Home`, folder/document create flows →
      `.claude/features/03-ui-phase2.md`
- [ ] **04 — Block editor — Phase 3** — `Screen_Detail`, paragraph block
      input/autosave/reorder → `.claude/features/04-block-editor-phase3.md`
- [ ] **05 — Markdown — Phase 4** — heading/list/checklist/blockquote/code
      block conversion, inline marks →
      `.claude/features/05-markdown-phase4.md`
- [ ] **06 — Quality pass — Phase 5** — macOS shortcuts, slash command,
      drag & drop, empty/error states, markdown export →
      `.claude/features/06-quality-phase5.md`

## Follow-ups (not part of the phase chain — anytime/in parallel)

- [ ] Install `swift-lsp` plugin (diagnostics on edit, go-to-definition)
- [ ] Adapt `/release` skill to `project.yml` `MARKETING_VERSION` +
      `xcodegen generate` (currently a stub ported from another project)
