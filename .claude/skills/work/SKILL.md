---
name: work
description: Run the semi:bold iOS feature pipeline for one work code — for the next not-done `.claude/features/<brief>.md` (in order), create/resume a relay branch `feature/<work-code>/<brief>` off `feature/<work-code>/base` (or the previous brief's branch), implement its unchecked Acceptance Criteria via feature-implementer + swift-reviewer, and open a chained PR. All brief-file bookkeeping (Status, checkboxes) happens only on `feature/<work-code>/base`, never on a relay branch, so brief PRs never carry brief-file changes. Once every brief is `done` and every brief's PR is merged into `feature/<work-code>/base`, clean up `.claude/features/` there.
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
  is `Status: done` **and** every brief's PR is merged into
  `feature/<work-code>/base`, check out `feature/<work-code>/base`,
  remove all `.claude/features/*.md` except `TEMPLATE.md`, and commit +
  push that to `feature/<work-code>/base`. The user then creates and
  merges the final `feature/<work-code>/base` → `dev` PR manually.
  Deleting these files before every PR is merged breaks the still-open
  ones with a modify/delete conflict.
- **⛔ Never push to `dev` or `main` directly.** This skill never merges
  or pushes to `dev` — the user controls when `feature/<work-code>/base`
  lands into `dev`.
- **A brief's `Status` field and Acceptance Criteria checkboxes are only
  ever edited on `feature/<work-code>/base` — never on a relay branch.**
  A relay branch's copy of its own brief file is frozen at whatever it
  was when the branch was created; nothing on that branch ever commits a
  change to it. This means a brief's PR (relay branch → previous branch
  or `base`) never has the brief file in its diff at all, so merging it
  can't conflict on that file — see "Workflow" step 4 and "Before
  Starting" step 9 for the checkout-base/edit/push/checkout-back
  mechanics this requires.

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
   - Read brief `Status` from **`feature/<work-code>/base`** specifically
     (`git show origin/feature/<work-code>/base:.claude/features/NN-slug.md`
     for a known slug, or check out `base` briefly to `ls`/`grep` across
     all of them) — never from whatever happens to be checked out
     locally, since only `base`'s copy is kept current.
   - If `[NN-slug]` was given, use that brief.
   - Otherwise, list `.claude/features/*.md` (as they exist on `base`)
     excluding `TEMPLATE.md`, ordered by filename (numbered briefs in
     numeric order first, then unnumbered alphabetically), and pick the
     first whose `Status` isn't `done`.
   - If every brief is `done`, check whether every brief's PR is already
     **merged** into `feature/<work-code>/base`:
     `git merge-base --is-ancestor origin/feature/<work-code>/<NN-slug>
     origin/feature/<work-code>/base` for each brief (exit code `0`
     means merged). All merged → skip straight to **Completion**. Any
     not yet merged → stop and tell the user their PRs are still pending
     merge; running `/work` again once they're all merged will trigger
     Completion automatically. **Never run Completion (delete the brief
     files) while any brief's PR is still open** — its branch still
     needs that file intact for the PR's own diff/merge, and `base`
     deleting it first causes a modify/delete conflict on that PR.
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
   Decisions & Deviations, and Acceptance Criteria drive everything
   below. The relay branch's copy is fine to read for this — Scope/
   Decisions/Screens & Flows never change after creation, so it's
   identical to `base`'s copy regardless of which branch you're on.
8. Read `CLAUDE.md` — useful context for your own commit/PR messages.
9. **If `Status: draft` or `ready`, flip it to `in-progress` — on
   `base`, not the relay branch you just created/resumed**:
   ```bash
   git checkout feature/<work-code>/base && git pull origin feature/<work-code>/base
   ```
   Edit `.claude/features/NN-slug.md`: `Status: draft`/`ready` →
   `Status: in-progress`.
   ```bash
   git add .claude/features/NN-slug.md
   git commit -m "chore(NN-slug): start feature"
   git push
   git checkout feature/<work-code>/<NN-slug>
   ```
   Switch back to the brief's own branch — everything from here on
   (reading source for implementation, the Workflow loop) happens there,
   except the checkbox edits in Workflow step 4, which repeat this same
   checkout-base/edit/push/checkout-back pattern.
10. List the brief's Acceptance Criteria items **from `base`'s copy**
    (`git show origin/feature/<work-code>/base:.claude/features/NN-slug.md`),
    noting which are already `[x]` (skip) vs `[ ]` (this run's work
    queue) — the relay branch's own copy may be stale on this point if
    you're resuming a brief whose earlier items were already checked off
    on `base` in a prior run.

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
   - **Never instruct it to write/record/document anything in the brief
     file** — not even "note this in Decisions & Deviations." It reports
     deviations/decisions/gaps in its own output text only. The brief
     file is frozen — only step 4 below (and only on `base`, never on
     this relay branch) ever changes it. If you catch yourself drafting
     a prompt that asks it to edit the brief, rewrite the prompt instead.

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

4. **Commit the code, then check off — on two different branches**
   - First, commit and push the actual code change on the brief's own
     relay branch (no brief-file edits bundled in):
     ```bash
     git add -A
     git commit -m "feat(NN-slug): <short summary of the AC item>"
     git push
     ```
   - Then, separately, record the checkbox on `base`:
     ```bash
     git checkout feature/<work-code>/base && git pull origin feature/<work-code>/base
     ```
     If `feature-implementer` confirms the item is fully met, edit the
     brief: change that item's `- [ ]` to `- [x]`. This is the **only**
     edit this step makes — don't touch Decisions & Deviations even to
     summarize what happened. If it's only partially done or blocked,
     leave it unchecked and add a note under Open Questions / Follow-ups
     explaining what's left instead.
     ```bash
     git add .claude/features/NN-slug.md
     git commit -m "chore(NN-slug): check off <short AC item summary>"
     git push
     git checkout feature/<work-code>/<NN-slug>
     ```
     Switch back to the relay branch before continuing to the next item.

5. Report progress (see User Communication).

If `feature-implementer` reports a gap (no matching wireframe/spec for a
UI-facing item, or an ambiguous brief decision), stop and report it to the
user instead of guessing — don't continue to the next item.

## After This Brief's Items Are Done

1. Re-read the brief's Acceptance Criteria **from `base`** (same
   pattern as step 9/Workflow step 4 — checkout base, pull). If every
   item is now `[x]`, update `Status: in-progress` → `done`; commit +
   push **on `base`**, then checkout back to the relay branch.
   - If some items remain unchecked (genuinely deferred follow-ups, not
     blocking), leave `Status: in-progress` and summarize what's left to
     the user.
2. Open the PR (from the relay branch, which has never touched the
   brief file — its diff is pure code):
   ```bash
   gh pr create --base <base-branch-from-step-5> --head feature/<work-code>/NN-slug \
     --title "<concise summary, under 70 chars>" \
     --body "<see PR Body Template>" \
     [--draft]   # use --draft if Acceptance Criteria aren't all met yet
   ```
3. Opening this brief's PR does **not** trigger Completion, even if it
   was the last not-done brief — Completion requires every brief's PR to
   already be **merged**, which can't be true the same run that just
   opened one of them. Tell the user this brief's PR is open; if it was
   the last brief, also tell them that once they've merged all the
   briefs' PRs in order (down to `feature/<work-code>/base`), running
   `/work` once more will detect that and run Completion automatically.

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

## Completion (every brief is `done` **and** every brief's PR is merged
into `feature/<work-code>/base` — see step 4's merge check)

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
  `feature/<work-code>/base` only once **every** brief is `done` **and**
  every brief's PR is merged into `base` — git history retains their
  content for reference. Deleting them on `base` any earlier breaks
  every still-open brief PR with a modify/delete conflict, since each
  one's own branch still has its (now further-edited) brief file.
- **A brief is frozen once written, and only `base` ever tracks its
  progress.** You (the orchestrator) only ever touch `Status` and the
  Acceptance Criteria checkboxes, and only on `feature/<work-code>/base`
  — never Scope, Decisions & Deviations, or Screens & Flows, and never
  any field at all on a relay branch. `feature-implementer` and
  `swift-reviewer` never touch the brief file at all, in any way. A
  relay branch's own copy of its brief is frozen the moment that branch
  is created — every Status/checkbox update happens via the
  checkout-base/edit/commit/push/checkout-back cycle in step 9 and
  Workflow step 4, so a brief's own PR diff never contains a brief-file
  change and can never conflict on one. If something worth recording
  comes up mid-work that doesn't fit a checkbox, say it in your own
  report to the user — don't put it in the brief.
- **⛔ Never push to `dev` or `main` directly.** The user merges PRs
  (in relay order) and creates the final `feature/<work-code>/base` →
  `dev` PR manually.
