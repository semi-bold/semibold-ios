# Feature: 01-project-structure-theming

Status: in-progress

## Source

- Feature spec: none (internal foundation work, from `TASKS.md` "Project
  structure & theming")
- Wireframes / planning specs: N/A — foundational change all screens
  depend on, not tied to one `Screen_*`/`Planning_N_*Flow`
- PLANNING.md sections: none directly; design tokens come from
  `../sketch-autokit/sketch/tokens.py`
- SERVICE.md sections: N/A

## Scope

- In scope:
  - Organize `semibold/` into `Models/`, `Views/`, `ViewModels/`, `Data/`
    groups (update `project.yml` source paths if the layout changes)
  - `AppTheme` design-tokens type ported from
    `../sketch-autokit/sketch/tokens.py` (colors, spacing, typography)
- Out of scope / deferred:
  - Implementing actual screens (see `ui-phase2`, `block-editor-phase3`,
    etc.) — this brief only sets up the structure/tokens they'll use

## Screens & Flows

N/A — shared infrastructure consumed by all subsequent screen work.

## Decisions & Deviations

- `project.yml` needs no changes for the `Models/`/`Views/`/`ViewModels/`/
  `Data/` split — its `sources: - path: semibold` entry with
  `createIntermediateGroups: true` already picks up new subdirectories.
- `App/` (containing `SemiboldApp.swift`, the `@main` entry point) remains
  as a fifth top-level group alongside the four required by this brief —
  it's app-lifecycle code, not a Model/View/ViewModel/Data file.

## Acceptance Criteria

- [x] `semibold/` split into `Models/`, `Views/`, `ViewModels/`, `Data/`
      groups
- [x] `AppTheme` type exists with colors/spacing/typography matching
      `sketch/tokens.py`
- [ ] `ContentView` (placeholder root view) uses `AppTheme` rather than
      hardcoded values, as a smoke test of the new type

## Open Questions / Follow-ups

- None yet
