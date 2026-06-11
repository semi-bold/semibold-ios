---
name: work
description: Run the semi:bold iOS feature pipeline — for the next not-done `.claude/features/<brief>.md` (in order), create a relay branch off `dev` (or the previous brief's branch), implement its unchecked Acceptance Criteria via feature-implementer + swift-reviewer, and open a chained PR. Once every brief is `done`, clean up `.claude/features/` on `dev`.
---

You are the work orchestrator for semi:bold iOS development.

When the user runs `/work [NN-slug]`, you process **one feature brief**
end to end: resolve/create its relay branch, implement its unchecked
Acceptance Criteria items via `feature-implementer` (reviewed by
`swift-reviewer`), and open a chained PR.

## Branch Model

- `main` ← `dev` ← `feature/<slug>` (relay chain): one branch per brief,
  each branched from the **previous brief's branch** in `.claude/features/`
  order — or from `dev` for the first brief processed.
- One PR per brief: base = the branch it was created from (`dev` for the
  first brief, the previous brief's branch otherwise). The user merges
  these PRs **in order**; each merge updates the next PR's diff down to
  just that brief's own changes.
- Once **every** brief in `.claude/features/` (excluding `TEMPLATE.md`)
  is `Status: done`, check out `dev`, remove all `.claude/features/*.md`
  except `TEMPLATE.md`, and commit + push that to `dev` directly. The
  user then opens the final `dev` → `main` PR manually.
- **⛔ Never push to or merge `main` directly.** Pushing the Completion
  cleanup commit straight to `dev` is the one exception to "always work
  on a feature branch" — it happens after all per-brief PRs already exist.

## Before Starting

0. **Sibling repo check** — `CLAUDE.md` and these briefs assume
   `../sketch-autokit` exists alongside this repo:
   ```bash
   ls ../sketch-autokit/docs
   ```
   If missing, stop and tell the user:
   ```
   ../sketch-autokit를 찾을 수 없습니다. README.md의 "Getting Started"를
   참고해 semibold-ios와 같은 부모 디렉토리에 sketch-autokit을 clone한 뒤
   다시 실행해 주세요.
   ```

1. **Ensure `dev` exists**:
   ```bash
   git fetch origin
   git rev-parse --verify origin/dev
   ```
   If it doesn't exist, create it from `main` and push:
   ```bash
   git checkout main && git pull origin main
   git checkout -b dev && git push -u origin dev
   ```

2. **Resolve the target brief**:
   - If `[NN-slug]` was given, use `.claude/features/NN-slug.md`.
   - Otherwise, list `.claude/features/*.md` excluding `TEMPLATE.md`,
     ordered by filename (numbered briefs in numeric order first, then
     unnumbered alphabetically), and pick the first whose `Status` isn't
     `done`.
   - If every brief is `done`, skip straight to **Completion**.
   - If the resolved brief's Source/Scope/Acceptance Criteria look
     unfilled (still template placeholders), stop and tell the user it
     needs to be fleshed out first — from `../sketch-autokit/docs/`
     (`PLANNING.md`, `SERVICE.md`, any notes there) plus the relevant
     `Screen_*`/`Planning_N_*Flow` — before this can implement it.

3. **Determine the relay base branch** for this brief:
   - Walk briefs in the same order as step 2, starting just before the
     resolved brief.
   - The base is the branch of the most recent preceding brief that has a
     `feature/<slug>` branch on `origin`
     (`git branch -r | grep "origin/feature/"`).
   - If none of the preceding briefs have a branch yet, base = `dev`.

4. **Create or resume the brief's branch**:
   - If `feature/<slug>` already exists on `origin` (resuming an
     in-progress brief), check it out and pull.
   - Otherwise create it from the base branch determined in step 3:
     ```bash
     git checkout <base-branch> && git pull origin <base-branch>
     git checkout -b feature/<slug>
     git push -u origin feature/<slug>
     ```

5. Read `.claude/features/NN-slug.md` in full — Scope, Screens & Flows,
   Decisions & Deviations, and Acceptance Criteria drive everything below.
6. Read `CLAUDE.md` — useful context for your own commit/PR messages.
7. If `Status: draft` or `ready`, set it to `Status: in-progress` and
   commit:
   ```bash
   git add .claude/features/NN-slug.md
   git commit -m "chore(NN-slug): start feature"
   git push
   ```
8. List the brief's Acceptance Criteria items, noting which are already
   `[x]` (skip) vs `[ ]` (this run's work queue).

## Workflow — per Acceptance Criteria item

For each unchecked (`- [ ]`) item, in order:

1. **Spawn `feature-implementer`**
   - `subagent_type: feature-implementer`
   - Prompt: the Acceptance Criteria item text verbatim, the brief path
     (`.claude/features/NN-slug.md`), and a note that it should read
     CLAUDE.md + the brief first (per its own instructions). If the item
     corresponds to a row in the brief's Screens & Flows table, mention
     that mapping explicitly.

2. **Spawn `swift-reviewer`**
   - `subagent_type: swift-reviewer`
   - Prompt: review the diff just produced (`git diff`) against
     CLAUDE.md and the brief's Decisions & Deviations / this Acceptance
     Criteria item.

3. **Handle the review result**
   - `OK` / `Suggested` only → continue.
   - `Blocking` → re-spawn `feature-implementer` with the blocking items
     as fix instructions. Retry up to 2 times total. If still blocking,
     stop and report the outstanding issues to the user.

4. **Check off and commit**
   - If `feature-implementer` confirms the item is fully met, edit the
     brief: change that item's `- [ ]` to `- [x]`.
   - If it's only partially done or blocked, leave it unchecked and add a
     note under Open Questions / Follow-ups explaining what's left.
   ```bash
   git add -A
   git commit -m "feat(NN-slug): <short summary of the AC item>"
   git push
   ```

5. Report progress (see User Communication).

If `feature-implementer` reports a gap (no matching wireframe/spec for a
UI-facing item, or an ambiguous brief decision), stop and report it to the
user instead of guessing — don't continue to the next item.

## After This Brief's Items Are Done

1. Re-read the brief's Acceptance Criteria. If every item is now `[x]`,
   update `Status: in-progress` → `done`; commit + push.
   - If some items remain unchecked (genuinely deferred follow-ups, not
     blocking), leave `Status: in-progress` and summarize what's left to
     the user.
2. Open the PR:
   ```bash
   gh pr create --base <base-branch-from-step-3> --head feature/<slug> \
     --title "<concise summary, under 70 chars>" \
     --body "<see PR Body Template>" \
     [--draft]   # use --draft if Acceptance Criteria aren't all met yet
   ```
3. If this brief is now `done` **and** it was the last not-done brief
   (every brief in `.claude/features/` is now `done`), proceed to
   **Completion**. Otherwise, tell the user this brief's PR is open and
   that running `/work` again will pick up the next brief, chained onto
   this one's branch.

### PR Body Template

```markdown
## Summary
<1-3 bullets from the brief's Scope>

## Acceptance Criteria
- [x] ...
- [x] ...
- [ ] ... (if any remain unmet — explain why)

🤖 Generated with `/work` from `.claude/features/NN-slug.md`
```

## Completion (every brief is `done`)

```bash
git checkout dev && git pull origin dev
find .claude/features/ -maxdepth 1 -name "*.md" ! -name "TEMPLATE.md" -delete
git add -A
git commit -m "chore: remove completed feature briefs"
git push
```

Report:

```
🎉 모든 feature brief 완료!

✅ 01-project-structure-theming — PR #N (base: dev)
✅ 02-local-db-phase1 — PR #M (base: feature/01-project-structure-theming)
...

각 PR을 base 순서대로 머지해 주세요 (dev까지 도달).
완료 후 dev → main Final PR은 직접 생성해 주세요.
```

## Agent Definitions

- `.claude/agents/feature-implementer.md` — implements one Acceptance
  Criteria item per invocation (UI screen/flow or non-UI task)
- `.claude/agents/swift-reviewer.md` — read-only review against
  CLAUDE.md + the brief

Spawn both via the Agent tool using their `name` as `subagent_type` —
they're already registered as project sub-agents, no need to paste their
instructions into the prompt.

## User Communication

After each Acceptance Criteria item:

```
📋 [WORK] feature/NN-slug (← <base-branch>) — 1/3: <AC item summary>
💻 [IMPLEMENTER] ... ✅
🔍 [REVIEWER] ... ✅ (OK)
🚀 [GIT] committed + pushed
```

When this brief's PR opens:

```
🎉 [WORK] feature/NN-slug complete

✅ <AC item 1>
✅ <AC item 2>
✅ <AC item 3>

Acceptance criteria: 3/3 met
✅ PR #N: <url> (base: <base-branch>)

다음 브리프를 진행하려면 /work 를 다시 실행해 주세요
(feature/NN-slug 위에 chain됩니다).
```

## Error Handling

- **`feature-implementer` reports a gap** → stop, report to user, don't
  proceed to the next item.
- **`swift-reviewer` finds Blocking issues after 2 retries** → stop,
  report outstanding issues, ask the user how to proceed.
- **git/`gh` step fails** → report the error, don't proceed, ask the
  user to resolve (auth, conflicts, etc.) before retrying.

## Tools You Can Use

- **Agent** — spawn `feature-implementer` / `swift-reviewer`
- **Read / Glob** — feature briefs, CLAUDE.md
- **Edit** — update a brief's Status and Acceptance Criteria checkboxes
- **Bash** — git branch/commit/push, `gh pr create`, Completion cleanup
- **TodoWrite** — track progress across items (recommended)

## Important Notes

- Execute Acceptance Criteria items **sequentially**, one at a time — not
  in parallel.
- One branch + one PR per brief, **chained via relay** (base = previous
  brief's branch, or `dev` for the first).
- `.claude/features/*.md` (except `TEMPLATE.md`) are removed from `dev`
  only once **every** brief is `done` — git history retains their content
  for reference.
- Don't edit a brief's Scope/Decisions/Screens & Flows sections — only
  `Status` and the Acceptance Criteria checkboxes.
- **⛔ Never push to or merge `main` directly.** The user merges PRs
  (in relay order) and opens the final `dev` → `main` PR manually.
