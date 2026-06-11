---
name: work
description: Start a semi:bold iOS feature — pick (or draft) a `.claude/features/` brief, create its feature branch, then hand off to /harness
---

You are the work session initializer for semi:bold iOS development.

When the user runs `/work`, you pick a feature brief from
`.claude/features/`, make sure it's ready to implement, create its
feature branch, and hand off to `/harness`.

## Workflow

### Step 0 — Sibling repo check

`CLAUDE.md` and these briefs assume `../sketch-autokit` exists as a
sibling repo (`semi-bold/semibold-ios` + `semi-bold/sketch-autokit`).
Check it before anything else:

```bash
ls ../sketch-autokit/docs
```

If it doesn't exist, stop and tell the user:

```
../sketch-autokit를 찾을 수 없습니다. README.md의 "Getting Started"를
참고해 semibold-ios와 같은 부모 디렉토리에 sketch-autokit을 clone한 뒤
다시 실행해 주세요.
```

### Step 1 — List feature briefs

- Glob `.claude/features/*.md`, excluding `TEMPLATE.md`.
- For each, read its `Status:` line and (if present) a `**Depends on:**`
  line.
- Ask the user (AskUserQuestion) which brief to work on. If there's an
  obvious next one — lowest-numbered brief that's `draft`/`ready` and
  whose dependency brief is `done` — offer it as the recommended option.

### Step 2 — New feature brief (only if the requested feature isn't in `.claude/features/`)

- Copy `.claude/features/TEMPLATE.md` to a new file. Per CLAUDE.md's
  numbering convention: prefix with the next `NN-` if it has an ordering
  dependency on existing phases, otherwise no prefix.
- Fill in Source/Scope/Screens & Flows from `../sketch-autokit/docs/`
  (`PLANNING.md`, `SERVICE.md`, and any other notes there — e.g. an
  Obsidian vault) plus the relevant `Screen_*`/`Planning_N_*Flow` and the
  user's description of what changed.
- Set `Status: draft` and show the user the draft for review — don't
  proceed to Step 3 until they confirm it's `ready`.

### Step 3 — Check readiness

- If `Status: draft`, ask the user to confirm it's ready (or refine it
  further) before creating a branch.
- If the brief's `**Depends on:**` line names another brief that isn't
  `Status: done`, warn the user but let them proceed if they choose to.

### Step 4 — Create the feature branch

```bash
git checkout main
git pull origin main
git checkout -b feature/NN-slug
git push -u origin feature/NN-slug
```

### Step 5 — Mark the brief in-progress

- Edit `.claude/features/NN-slug.md`: `Status: ready` → `Status:
  in-progress`.

```bash
git add .claude/features/NN-slug.md
git commit -m "chore(NN-slug): start feature"
git push
```

### Step 6 — Hand off

```
✅ feature/NN-slug 브랜치 생성 + push 완료
✅ .claude/features/NN-slug.md → in-progress

/harness 를 실행하면 Acceptance Criteria 항목 순서대로 구현이 진행됩니다.
```

---

## Tools You Can Use

- **AskUserQuestion** — pick a brief / confirm new-brief details
- **Read / Glob** — list and read `.claude/features/*.md`
- **Write / Edit** — draft a new brief from `TEMPLATE.md`, update Status
- **Bash** — git branch/push

---

## Important Notes

- One feature brief = one branch (`feature/NN-slug`) = one PR (created by
  `/harness`).
- Base is always `main` — there's no `dev` branch in this repo.
- Don't skip Step 3 — an `in-progress` brief with unresolved dependencies
  or ambiguity is the most common cause of `feature-implementer` gaps
  later.
