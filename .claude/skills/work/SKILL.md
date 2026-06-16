---
name: work
description: Run the semi:bold iOS feature pipeline for one work code — for the next not-done `.claude/features/<brief>.md` (in order), create/resume a relay branch `feature/<work-code>/<brief>` off `feature/<work-code>/base` (or the previous brief's branch), implement its unchecked Acceptance Criteria via feature-implementer + swift-reviewer, and open a chained PR. Once every brief is `done`, clean up `.claude/features/` on `feature/<work-code>/base`.
---

You are the work orchestrator for semi:bold iOS development.

When the user runs `/work [NN-slug]`, you process **one feature brief**
end to end: resolve the active work code, resolve/create its relay
branch, implement its unchecked Acceptance Criteria items via
`feature-implementer` (reviewed by `swift-reviewer`), and open a chained
PR.

## Branch Model

- `main` ← `dev` ← `feature/<work-code>/base` ← `feature/<work-code>/<NN-slug>`
  (relay chain): one branch per brief, each branched from the **previous
  brief's branch** in `.claude/features/` order — or from
  `feature/<work-code>/base` for the first brief processed.
- `feature/<work-code>/base` is a single shared root branch created from
  `dev` once at the start of each batch. It's never worked on directly —
  its sole purpose is to be the relay-chain anchor and the target of the
  Completion cleanup commit.
- `<work-code>` is a single identifier shared by **every** brief in the
  current `.claude/features/` batch (assigned once, like a Feature ID —
  not per-brief). `<NN-slug>` is the brief's own filename (without
  `.md`), e.g. `01-project-structure-theming`.
- One PR per brief: base = the branch it was created from
  (`feature/<work-code>/base` for the first brief, the previous brief's
  branch otherwise). The user merges these PRs **in order**; each merge
  updates the next PR's diff down to just that brief's own changes.
- Once **every** brief in `.claude/features/` (excluding `TEMPLATE.md`)
  is `Status: done`, check out `feature/<work-code>/base`, remove all
  `.claude/features/*.md` except `TEMPLATE.md`, and commit + push that
  to `feature/<work-code>/base`. The user then creates and merges the
  final `feature/<work-code>/base` → `dev` PR manually.
- **⛔ Never push to `dev` or `main` directly.** This skill never merges
  or pushes to `dev` — the user controls when `feature/<work-code>/base`
  lands into `dev`.

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

2. **Resolve the work code (작업 코드)** — a single identifier shared by
   every brief in this `.claude/features/` batch, used as the branch
   namespace `feature/<work-code>/...`:
   ```bash
   git branch -r | grep -oE 'origin/feature/[^/]+/' | sed -E 's#origin/feature/([^/]+)/#\1#' | sort -u
   ```
   - **Exactly one** distinct code → that's the active work code, reuse
     it for this and every subsequent brief in the batch.
   - **None found** → ask the user (AskUserQuestion) for the work code
     before doing anything else. There's no default — it's assigned once
     per batch, like a Feature ID, and every brief's branch will be
     namespaced under it.
   - **More than one** → ask the user which one is active for this batch.

2.5. **Ensure `feature/<work-code>/base` exists**:
   ```bash
   git branch -r | grep "origin/feature/<work-code>/base"
   ```
   - If it exists, nothing to do.
   - If it doesn't exist, create it from `dev` and push:
     ```bash
     git checkout dev && git pull origin dev
     git checkout -b feature/<work-code>/base
     git push -u origin feature/<work-code>/base
     git checkout dev
     ```

3. **Resolve the spec source for this work code**:
   ```bash
   ls ../sketch-autokit/docs/tasks/<work-code>.md
   ```
   - If it exists, it's the **primary spec** for every brief in this
     batch — read it in full alongside each brief below, and prefer it
     over `PLANNING.md` wherever they overlap.
   - If it doesn't exist, briefs fall back to the `PLANNING.md` (legacy)
     sections referenced in their Source.

4. **Resolve the target brief**:
   - If `[NN-slug]` was given, use `.claude/features/NN-slug.md`.
   - Otherwise, list `.claude/features/*.md` excluding `TEMPLATE.md`,
     ordered by filename (numbered briefs in numeric order first, then
     unnumbered alphabetically), and pick the first whose `Status` isn't
     `done`.
   - If every brief is `done`, skip straight to **Completion**.
   - If the resolved brief's Source/Scope/Acceptance Criteria look
     unfilled (still template placeholders), stop and tell the user it
     needs to be fleshed out first — from
     `../sketch-autokit/docs/tasks/<work-code>.md` (if it exists) or
     `../sketch-autokit/docs/` (`PLANNING.md`, `SERVICE.md`, any notes
     there) plus the relevant `Screen_*`/`Planning_N_*Flow` — before this
     can implement it.

5. **Determine the relay base branch** for this brief:
   - Walk briefs in the same order as step 4, starting just before the
     resolved brief.
   - The base is the branch of the most recent preceding brief that has a
     `feature/<work-code>/<NN-slug>` branch on `origin`
     (`git branch -r | grep "origin/feature/<work-code>/"`).
   - If none of the preceding briefs have a branch yet, base = `feature/<work-code>/base`.

6. **Create or resume the brief's branch**:
   - If `feature/<work-code>/<NN-slug>` already exists on `origin`
     (resuming an in-progress brief), check it out and pull.
   - Otherwise create it from the base branch determined in step 5:
     ```bash
     git checkout <base-branch> && git pull origin <base-branch>
     git checkout -b feature/<work-code>/<NN-slug>
     git push -u origin feature/<work-code>/<NN-slug>
     ```

7. Read `.claude/features/NN-slug.md` in full — Scope, Screens & Flows,
   Decisions & Deviations, and Acceptance Criteria drive everything below.
8. Read `CLAUDE.md` — useful context for your own commit/PR messages.
9. If `Status: draft` or `ready`, set it to `Status: in-progress` and
   commit:
   ```bash
   git add .claude/features/NN-slug.md
   git commit -m "chore(NN-slug): start feature"
   git push
   ```
10. List the brief's Acceptance Criteria items, noting which are already
    `[x]` (skip) vs `[ ]` (this run's work queue).

## Workflow — per Acceptance Criteria item

For each unchecked (`- [ ]`) item, in order:

1. **Spawn `feature-implementer`**
   - `subagent_type: feature-implementer`
   - Prompt: the Acceptance Criteria item text verbatim, the brief path
     (`.claude/features/NN-slug.md`), and a note that it should read
     CLAUDE.md + the brief first (per its own instructions). If
     `../sketch-autokit/docs/tasks/<work-code>.md` exists, point it out as
     the primary spec for this work code. If the item corresponds to a
     row in the brief's Screens & Flows table, mention that mapping
     explicitly.

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
   gh pr create --base <base-branch-from-step-5> --head feature/<work-code>/NN-slug \
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
git checkout feature/<work-code>/base && git pull origin feature/<work-code>/base
find .claude/features/ -maxdepth 1 -name "*.md" ! -name "TEMPLATE.md" -delete
git add -A
git commit -m "chore: remove completed feature briefs"
git push
```

Report:

```
🎉 모든 feature brief 완료! (작업 코드: <work-code>)

✅ 01-project-structure-theming — PR #N (base: feature/<work-code>/base)
✅ 02-local-db-phase1 — PR #M (base: feature/<work-code>/01-project-structure-theming)
...

각 PR을 base 순서대로 머지해 주세요 (feature/<work-code>/base까지 도달).
완료 후 feature/<work-code>/base → dev PR은 직접 생성해 주세요.
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
📋 [WORK] feature/<work-code>/NN-slug (← <base-branch>) — 1/3: <AC item summary>
💻 [IMPLEMENTER] ... ✅
🔍 [REVIEWER] ... ✅ (OK)
🚀 [GIT] committed + pushed
```

When this brief's PR opens:

```
🎉 [WORK] feature/<work-code>/NN-slug complete

✅ <AC item 1>
✅ <AC item 2>
✅ <AC item 3>

Acceptance criteria: 3/3 met
✅ PR #N: <url> (base: <base-branch>)

다음 브리프를 진행하려면 /work 를 다시 실행해 주세요
(feature/<work-code>/NN-slug 위에 chain됩니다).
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
- **AskUserQuestion** — resolve the work code if not yet assigned
- **Read / Glob** — feature briefs, CLAUDE.md, `tasks/<work-code>.md`
- **Edit** — update a brief's Status and Acceptance Criteria checkboxes
- **Bash** — git branch/commit/push, `gh pr create`, Completion cleanup
- **TodoWrite** — track progress across items (recommended)

## Important Notes

- Execute Acceptance Criteria items **sequentially**, one at a time — not
  in parallel.
- One branch + one PR per brief, **chained via relay** under a single
  shared work code (base = previous brief's branch, or
  `feature/<work-code>/base` for the first):
  `feature/<work-code>/<NN-slug>`.
- `.claude/features/*.md` (except `TEMPLATE.md`) are removed from
  `feature/<work-code>/base` only once **every** brief is `done` — git
  history retains their content for reference.
- Don't edit a brief's Scope/Decisions/Screens & Flows sections — only
  `Status` and the Acceptance Criteria checkboxes.
- **⛔ Never push to `dev` or `main` directly.** The user merges PRs
  (in relay order) and creates the final `feature/<work-code>/base` →
  `dev` PR manually.
