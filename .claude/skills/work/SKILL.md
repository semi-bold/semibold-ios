---
name: work
description: Run the semi:bold iOS feature pipeline — picks up the next unimplemented brief from .claude/features/, implements its Acceptance Criteria via feature-implementer + swift-reviewer, and opens a chained PR. Run /brief <work-code> first to generate briefs.
---

You are the work orchestrator for semi:bold iOS development.

## Invocation

```
/work           # implements the next pending brief
/work <NN-slug> # implements a specific brief by name
```

Briefs must already exist in `.claude/features/`. Run `/brief <work-code>` first if they don't.

## Branch Model

```
main ← dev ← feature/<work-code>/base ← feature/<work-code>/<NN-slug> ← ...
```

- One branch + one PR per brief, chained via relay.
- `feature/<work-code>/base` is created by `/brief` — never touched here.
- **⛔ Never push to `dev` or `main` directly.**
- "Implementation done" = PR exists (open or merged), checked via `git`/`gh`.

---

## Steps

### 1. Verify briefs exist

```bash
find .claude/features/ -maxdepth 1 -name "*.md" ! -name "TEMPLATE.md"
```
None found → stop:
```
.claude/features/에 브리프가 없습니다.
/brief <work-code> 를 먼저 실행해 주세요.
```

### 2. Resolve work code

```bash
git branch -r | grep -oE 'origin/feature/[^/]+/base' \
  | sed -E 's#origin/feature/([^/]+)/base#\1#' | sort -u
```
- Exactly one → that's the work code.
- None → stop and tell the user to run `/brief <work-code>` first.
- More than one → ask the user which is active (AskUserQuestion).

### 3. Resolve the target brief

List `.claude/features/*.md` excluding `TEMPLATE.md` in filename order
(numbered briefs first). For each brief:

```bash
git branch -r | grep "origin/feature/<work-code>/<NN-slug>"
gh pr list --head "feature/<work-code>/<NN-slug>" --json number,state
```

- **No branch** → not started → this is the target.
- **Branch, no PR** → in-progress (interrupted) → resume. Check already-done AC items:
  ```bash
  git log <base>..feature/<work-code>/<NN-slug> --oneline
  ```
- **PR exists (open or merged)** → done, check the next brief.
- **Every brief has a PR** → go to **Completion**.
- **Open Questions present** → stop, ask the user before proceeding.

### 4. Determine relay base branch

Walk preceding briefs (in filename order). The base is the branch of the most
recent preceding brief that has a remote branch on `origin`. If none →
base = `feature/<work-code>/base`.

### 5. Create or resume the brief's branch

Resuming (branch exists on origin):
```bash
git checkout feature/<work-code>/<NN-slug> && git pull
```

Creating fresh:
```bash
git checkout <base-branch> && git pull origin <base-branch>
git checkout -b feature/<work-code>/<NN-slug>
git push -u origin feature/<work-code>/<NN-slug>
```

### 6. Read spec + brief

```bash
cat ../sketch-autokit/docs/tasks/<work-code>.md   # primary spec (if exists)
cat .claude/features/<NN-slug>.md                  # brief
cat CLAUDE.md                                       # conventions
```

List AC items from the brief. Mark which already have a `feat(<NN-slug>): ...`
commit (skip) vs which don't (this run's work queue).

---

## Per Acceptance Criteria Item

For each unimplemented AC item, in order:

**1. Spawn `feature-implementer`**
- `subagent_type: feature-implementer`
- Prompt includes: the AC item text verbatim, brief path, note to read CLAUDE.md
  and the brief first, path to `../sketch-autokit/docs/tasks/<work-code>.md` as
  primary spec, and the Screens & Flows row if applicable.
- Never instruct it to edit the brief file.

**2. Spawn `swift-reviewer`**
- `subagent_type: swift-reviewer`
- Reviews the diff against CLAUDE.md and the brief's Decisions & Deviations.

**3. Handle review result**
- `OK` / `Suggested` → continue.
- `Blocking` → re-spawn `feature-implementer` with blocking items as fix
  instructions. Up to 2 retries. Still blocking → stop, report to user.

**4. Commit**
```bash
git add -A
git commit -m "feat(<NN-slug>): <short summary of AC item>"
git push
```

**5. Report**
```
📋 [WORK] feature/<work-code>/<NN-slug> (← <base>) — 2/5: <AC item summary>
💻 [IMPLEMENTER] ... ✅
🔍 [REVIEWER] ... ✅ (OK)
🚀 [GIT] committed + pushed
```

Gap reported by `feature-implementer` (no spec/wireframe, ambiguous decision) →
stop and report to user. Do not guess.

---

## After All AC Items Are Done

**Open the PR:**
```bash
gh pr create \
  --base <relay-base> \
  --head "feature/<work-code>/<NN-slug>" \
  --title "<concise summary under 70 chars>" \
  --body "$(cat <<'EOF'
## Summary
<1-3 bullets from brief Scope>

## Acceptance Criteria
- [x] ...

🤖 Generated with `/work` from `.claude/features/<NN-slug>.md`
EOF
)"
```
Use `--draft` if any AC item remains unmet.

**Check remaining briefs.** Any without a PR → stop:
```
🎉 [WORK] feature/<work-code>/<NN-slug> complete

✅ <AC 1>
✅ <AC 2>
...
Acceptance criteria: N/N met
✅ PR #N: <url> (base: <base-branch>)

다음 브리프를 진행하려면 /work 를 다시 실행해 주세요.
```

**Last brief done → Completion (same run).**

---

## Completion (every brief has a PR)

```bash
git checkout feature/<work-code>/base && git pull origin feature/<work-code>/base
find .claude/features/ -maxdepth 1 -name "*.md" ! -name "TEMPLATE.md" -delete
git add -A
git commit -m "chore: remove completed feature briefs (<work-code>)"
git push
```

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
- **AskUserQuestion** — ambiguous work code, unresolved Open Questions
- **Read / Bash / Glob** — spec, briefs, CLAUDE.md, git/gh
- **TodoWrite** — track progress across AC items (recommended)

## Notes

- AC items run **sequentially**, one at a time.
- Briefs are never edited after creation.
- **⛔ Never push to `dev` or `main`.**
