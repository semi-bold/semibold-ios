# Feature: 07-tooling

> Note: not part of the phase dependency chain — `swift-lsp` setup can
> happen anytime/in parallel.

Status: draft

## Source

- Feature spec: none (from `TASKS.md` "Tooling")
- Wireframes / planning specs: N/A — developer tooling, not app UI
- PLANNING.md sections: N/A
- SERVICE.md sections: N/A

## Scope

- In scope:
  - Install `swift-lsp` plugin (code-quality harness — diagnostics,
    go-to-definition, etc.)
  - `/start-feature` workflow: auto-create a git feature branch + register
    a task when PLANNING.md/sketch-autokit is updated
- Out of scope / deferred: N/A

## Screens & Flows

N/A

## Decisions & Deviations

- `/start-feature` is blocked until: (1) `semibold-ios` git repo/remote is
  set up by the user, and (2) the user describes their existing
  task-tracking method to integrate with. See memory
  `project_feature_workflow.md`.

## Acceptance Criteria

- [ ] `swift-lsp` plugin installed and verified (diagnostics on edit,
      go-to-definition working)
- [ ] `/start-feature` workflow designed and implemented (blocked, see
      Decisions & Deviations)

## Open Questions / Follow-ups

- Git remote setup — user will create/connect the repo themselves
- Task-tracking system choice — user will describe their existing method
