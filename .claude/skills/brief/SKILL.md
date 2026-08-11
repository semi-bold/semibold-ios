---
name: brief
description: Reads the spec for a semi:bold work code from semibold-docs, creates feature/[work-code]/base from dev, and writes feature briefs to .claude/features/ — one per implementation unit, ordered by dependency. Run this once per batch before /work.
---

You are the brief generator for semi:bold iOS development.

## Invocation

```
/brief <work-code>   # e.g. /brief NO-004
```

`<work-code>` is required. If omitted, ask the user (AskUserQuestion) before continuing.

## What This Skill Does

Reads `../semibold-docs/tasks/<work-code>.md`, derives one feature brief per
implementation unit, writes them to `.claude/features/`, and commits them to
`feature/<work-code>/base`. After this, run `/work` to implement each brief.

---

## Steps

### 1. Validate inputs

```bash
ls ../semibold-docs/tasks
```
Missing → stop:
```
../semibold-docs를 찾을 수 없습니다. semibold-ios와 같은 부모 디렉토리에
semibold-docs를 clone한 뒤 다시 실행해 주세요.
```

```bash
git fetch origin && git rev-parse --verify origin/dev
```
`dev` missing → create from `main`:
```bash
git checkout main && git pull origin main
git checkout -b dev && git push -u origin dev
```

### 2. Read the spec

```bash
cat ../semibold-docs/tasks/<work-code>.md
```
Missing → stop:
```
../semibold-docs/tasks/<work-code>.md 파일을 찾을 수 없습니다.
/brief를 실행하기 전에 semibold-docs에 스펙 파일을 작성해 주세요.
```

Read the file in full. It is the authoritative source for everything below.

### 3. Create `feature/<work-code>/base`

```bash
git branch -r | grep "origin/feature/<work-code>/base"
```
- Exists → check it out and pull:
  ```bash
  git checkout feature/<work-code>/base && git pull origin feature/<work-code>/base
  ```
- Missing → create from `dev`:
  ```bash
  git checkout dev && git pull origin dev
  git checkout -b feature/<work-code>/base
  git push -u origin feature/<work-code>/base
  ```

### 4. Check for existing briefs

```bash
find .claude/features/ -maxdepth 1 -name "*.md" ! -name "TEMPLATE.md"
```
If files exist → stop:
```
.claude/features/에 이미 브리프가 있습니다.
/work를 실행하면 구현이 시작됩니다.
새 배치를 시작하려면 기존 브리프를 먼저 정리해 주세요.
```

### 5. Generate briefs

Derive one brief per distinct implementation unit from the spec. Guidelines:
- **Granularity**: one brief ≈ one screen or one self-contained technical change —
  something a single `feature-implementer` invocation can handle.
- **Ordering**: number by dependency — data-layer changes come before UI screens
  that use them; use two-digit prefixes (`01-`, `02-`, …).
- **Naming**: `<NN>-<kebab-slug>.md`, e.g. `01-auth-session.md`.

For each brief, write `.claude/features/<NN-slug>.md` using `TEMPLATE.md` structure:

```markdown
# Feature: <NN-slug>

## Source
- tasks/<work-code>.md §...
- Wireframes: <name> (or "아직 wireframe.py에 없음 — spec §X.Y 설명 기준으로 구현")
- PLANNING.md §... (legacy, if applicable)

## Scope
- In scope: ...
- Out of scope / deferred: ...

## Screens & Flows
| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|

## Decisions & Deviations
- <decision> — <why>

## Acceptance Criteria
- [ ] ...

## Open Questions / Follow-ups
- <anything requiring human confirmation before implementation>
```

**Note on wireframes**: if `../semibold-docs/tasks/<work-code>.md` §8 lists
wireframe additions as pending (e.g. "screens/wireframe.py — X 신규 추가 필요"),
note this in the brief and implement from the spec's screen-description section instead.
Do not block implementation on missing wireframes when the spec gives enough detail.

### 6. Commit briefs to base

```bash
git add .claude/features/
git commit -m "chore(<work-code>): add feature briefs from spec"
git push
```

### 7. Report and stop

```
📋 [BRIEF] <work-code> — 브리프 생성 완료

브랜치: feature/<work-code>/base
커밋: <hash>

브리프 목록:
  01-<slug>  AC: N개
  02-<slug>  AC: M개
  ...

Open Questions가 있는 브리프:
  0N-<slug>: <question summary>

구현을 시작하려면 /work 를 실행해 주세요.
```

Always stop here — do not start implementation.

---

## Tools

- **Read / Bash** — spec files, git commands, directory checks
- **Write** — `.claude/features/<NN-slug>.md` brief files
- **AskUserQuestion** — if work code is missing

## Notes

- **⛔ Never push to `dev` or `main` directly.**
- Briefs are written once and never edited again after `/work` starts implementing them.
- If the spec has unresolved decisions that block a specific brief's AC items, flag them
  as Open Questions in that brief — `/work` will stop and ask the user before implementing it.
