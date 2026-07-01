---
name: work
description: Run the semi:bold iOS feature pipeline for one work code — reads the spec from sketch-autokit, generates feature briefs, creates the relay branch, implements each brief's Acceptance Criteria via feature-implementer + swift-reviewer, and opens chained PRs.
---

You are the work orchestrator for semi:bold iOS development.

## Invocation

```
/work [work-code]   # e.g. /work NO-004
/work               # resumes the in-progress batch (briefs already in .claude/features/)
```

## Branch Model

```
main ← dev ← feature/<work-code>/base ← feature/<work-code>/<NN-slug> ← ...
```

- `feature/<work-code>/base` — created once from `dev`, anchors the relay chain.
  Briefs are committed here, then each brief gets its own relay branch.
- `feature/<work-code>/<NN-slug>` — one branch per brief, chained from the
  previous brief's branch (or `base` for the first).
- One PR per brief. The user merges PRs **in order**; each merge lets the
  next PR's diff show only that brief's own changes.
- **⛔ Never push to `dev` or `main` directly.**
- Briefs are written once to `.claude/features/` on `base` and never edited
  again. "Implementation done" = PR exists (open or merged), checked via
  `git`/`gh` — not by looking at the brief file.

---

## Phase 1 — Setup

### Step 1: Sibling repo check
```bash
ls ../sketch-autokit/docs
```
Missing → stop and tell the user to clone sketch-autokit alongside semibold-ios.

### Step 2: Ensure `dev` exists
```bash
git fetch origin
git rev-parse --verify origin/dev
```
If missing, create from `main` and push.

### Step 3: Resolve the work code

**A. If `/work <work-code>` was given** → use it directly. Skip to step 4.

**B. If `/work` was called without an argument:**
- Check if `.claude/features/` has any `*.md` other than `TEMPLATE.md`:
  ```bash
  find .claude/features/ -maxdepth 1 -name "*.md" ! -name "TEMPLATE.md"
  ```
  - Files found → briefs already exist from a previous run. Infer the work code
    from the existing `feature/*/base` branch:
    ```bash
    git branch -r | grep -oE 'origin/feature/[^/]+/base' \
      | sed -E 's#origin/feature/([^/]+)/base#\1#' | sort -u
    ```
    If exactly one → that's the active work code, skip to **Phase 2**.
    If more than one → ask which is active (AskUserQuestion).
  - No files → **ask the user for the work code** (AskUserQuestion) before
    continuing. There is no default.

### Step 4: Read the spec
```bash
cat ../sketch-autokit/docs/tasks/<work-code>.md
```
- **If the file exists** → this is the primary spec for the entire batch.
  Read it in full. It drives brief generation (step 5) and all implementation
  decisions downstream.
- **If it doesn't exist** → stop and tell the user: the spec file
  `docs/tasks/<work-code>.md` must exist in sketch-autokit before `/work`
  can generate briefs. Offer to help create it.

### Step 5: Ensure `feature/<work-code>/base` exists
```bash
git branch -r | grep "origin/feature/<work-code>/base"
```
- Exists → check it out and pull. Skip to step 6.
- Missing → create from `dev`:
  ```bash
  git checkout dev && git pull origin dev
  git checkout -b feature/<work-code>/base
  git push -u origin feature/<work-code>/base
  ```

### Step 6: Generate briefs (first run only)

**Skip this step if `.claude/features/` already has non-TEMPLATE briefs** —
that means a previous run already generated them.

Otherwise, derive briefs from the spec read in step 4:
- Identify distinct implementation units: each new screen, each backend
  change, each data-layer refactor. Use judgment about granularity — a brief
  should be a coherent chunk one `feature-implementer` invocation can handle
  (roughly a screen or a self-contained technical change).
- Order them by dependency: UI screens that depend on data-layer changes come
  after those changes; use two-digit prefixes (`01-`, `02-`, …) to encode
  the order.
- For each brief, write a `.claude/features/<NN-slug>.md` file using
  `TEMPLATE.md` as the structure. Fill in:
  - **Source**: `tasks/<work-code>.md` section(s) + wireframe/planning refs
  - **Scope**: in scope / out of scope derived from the spec
  - **Screens & Flows**: wireframe/planning spec → SwiftUI target mapping
  - **Acceptance Criteria**: concrete, testable items (the
    `feature-implementer` will implement these one by one)
  - **Decisions & Deviations**: any choices the spec leaves open that
    need a committed answer before implementation starts
  - **Open Questions**: anything that needs human confirmation before the
    brief can proceed

After writing all briefs, **commit them to `feature/<work-code>/base`**:
```bash
git add .claude/features/
git commit -m "chore(<work-code>): add feature briefs from spec"
git push
```

Then show the user a summary:
```
📋 [WORK] <work-code> — 브리프 생성 완료

01-<slug>  Acceptance Criteria: N items
02-<slug>  Acceptance Criteria: M items
...

Open Questions가 있는 브리프:
  01-<slug>: <question summary>

계속 진행하려면 /work 를 다시 실행해 주세요.
Open Questions가 있는 브리프는 사용자 확인 후 진행하도록 멈춥니다.
```

**Stop here after brief generation.** The user reviews the briefs and re-runs
`/work` to begin implementation. If any brief has unresolved Open Questions,
stop at that brief during Phase 2 and ask the user.

---

## Phase 2 — Implementation

This phase runs on every `/work` call after briefs exist (including the call
immediately after brief generation, if the user re-runs).

### Step 7: Resolve the target brief

List `.claude/features/*.md` excluding `TEMPLATE.md` in filename order
(numbered briefs first). For each:
```bash
git branch -r | grep "origin/feature/<work-code>/<NN-slug>"
gh pr list --head "feature/<work-code>/<NN-slug>" --json number,state
```

- **No branch** → not started → this is the target brief.
- **Branch, no PR** → in-progress (interrupted) → resume. Check which AC
  items already have a `feat(<NN-slug>): ...` commit:
  ```bash
  git log <base>..feature/<work-code>/<NN-slug> --oneline
  ```
- **PR exists (open or merged)** → done, check the next brief.
- **Every brief has a PR** → skip to **Completion**.
- **Open Questions unresolved** → stop, ask the user before proceeding.

### Step 8: Determine relay base branch

The base is the branch of the most recent preceding brief that has a remote
branch on `origin`. If no preceding brief has a branch yet → base =
`feature/<work-code>/base`.

### Step 9: Create or resume the brief's branch

If the branch already exists on `origin` (resuming):
```bash
git checkout feature/<work-code>/<NN-slug> && git pull
```

Otherwise create from the relay base:
```bash
git checkout <base-branch> && git pull origin <base-branch>
git checkout -b feature/<work-code>/<NN-slug>
git push -u origin feature/<work-code>/<NN-slug>
```

### Step 10: Read CLAUDE.md + brief

Read `CLAUDE.md` for conventions, then read the target brief in full
(Scope, Screens & Flows, Decisions & Deviations, Acceptance Criteria).
Also re-read `../sketch-autokit/docs/tasks/<work-code>.md` for detail the
brief may not restate.

---

## Per Acceptance Criteria Item

For each unimplemented AC item (in order):

**1. Spawn `feature-implementer`**
- `subagent_type: feature-implementer`
- Prompt: the AC item text verbatim + brief path + note to read CLAUDE.md and
  the brief first. Point to `../sketch-autokit/docs/tasks/<work-code>.md` as
  the primary spec. If the item maps to a row in Screens & Flows, say so.
- Never instruct it to edit the brief file.

**2. Spawn `swift-reviewer`**
- `subagent_type: swift-reviewer`
- Prompt: review the diff against CLAUDE.md and the brief's Decisions &
  Deviations for this AC item.

**3. Handle review result**
- `OK` / `Suggested` → continue.
- `Blocking` → re-spawn `feature-implementer` with the blocking items as fix
  instructions. Retry up to 2 times. Still blocking → stop, report to user.

**4. Commit**
```bash
git add -A
git commit -m "feat(<NN-slug>): <short summary of AC item>"
git push
```

**5. Report progress**
```
📋 [WORK] feature/<work-code>/<NN-slug> (← <base>) — 1/3: <AC item summary>
💻 [IMPLEMENTER] ... ✅
🔍 [REVIEWER] ... ✅ (OK)
🚀 [GIT] committed + pushed
```

If `feature-implementer` reports a gap (no matching wireframe/spec, or an
ambiguous brief decision) → stop and report to the user. Do not guess.

---

## After All AC Items Are Done

**1. Open the PR:**
```bash
gh pr create \
  --base <relay-base-from-step-8> \
  --head "feature/<work-code>/<NN-slug>" \
  --title "<concise summary under 70 chars>" \
  --body "$(cat <<'EOF'
## Summary
<1-3 bullets from the brief's Scope>

## Acceptance Criteria
- [x] ...

🤖 Generated with `/work` from `.claude/features/<NN-slug>.md`
EOF
)"
```
Use `--draft` if any AC item remains unmet.

**2. Check for remaining briefs.** If any brief still has no PR → stop:
```
🎉 [WORK] feature/<work-code>/<NN-slug> complete

✅ <AC item 1>
✅ <AC item 2>

Acceptance criteria: N/N met
✅ PR #N: <url> (base: <base-branch>)

다음 브리프를 진행하려면 /work 를 다시 실행해 주세요.
```

**3. If this was the last brief with no PR → Completion (same run).**

---

## Completion (every brief has a PR)

```bash
git checkout feature/<work-code>/base && git pull origin feature/<work-code>/base
find .claude/features/ -maxdepth 1 -name "*.md" ! -name "TEMPLATE.md" -delete
git add -A
git commit -m "chore: remove completed feature briefs (<work-code>)"
git push
```

Report:
```
🎉 모든 feature brief 완료! (작업 코드: <work-code>)

✅ 01-<slug> — PR #N (base: feature/<work-code>/base)
✅ 02-<slug> — PR #M (base: feature/<work-code>/01-<slug>)
...

각 PR을 순서대로 머지해 주세요.
완료 후 feature/<work-code>/base → dev PR은 직접 생성해 주세요.
```

---

## Tools

- **Agent** — `feature-implementer`, `swift-reviewer`
- **AskUserQuestion** — work code, unresolved Open Questions
- **Read / Bash / Glob** — spec files, briefs, CLAUDE.md, git/gh commands
- **Write / Edit** — write briefs to `.claude/features/` during step 6
- **TodoWrite** — track progress across AC items (recommended)

## Notes

- AC items run **sequentially**, one at a time.
- The spec file (`tasks/<work-code>.md`) is the authoritative source;
  briefs are derived from it and must not contradict it.
- Briefs are never edited after being committed — decisions/deviations go in
  the PR body or are reported to the user, not written back to the brief.
- **⛔ Never push to `dev` or `main`.**
