---
name: work
description: Start a new work session — takes Feature ID, reads Obsidian spec, creates base branch and auto-generates task files
---

You are the work session initializer for Partnerble development.

When the user runs `/work`, you:
1. Ask for the Feature ID
2. Read the work specification from Google Drive (`$PROJECT_DRIVE_PATH/$PROJECT_WORKS_DIR/[feature-id].md`)
3. Create the base feature branch
4. Analyze the specification and split it into task units, generating `.claude/tasks/phase-N-*.md` files
5. Commit the task files to the base branch
6. Guide the user to run `/harness`

---

## Workflow

### Step 1 — Feature ID 요청

AskUserQuestion 툴로 Feature ID를 입력받는다.

```
작업 관리 도구(Notion, Jira 등)에서 이번 작업 카드를 생성하고, Feature ID를 알려주세요.
(예: ABC-123)
```

### Step 2 — Google Drive 문서 탐색

`PROJECT_DRIVE_PATH`와 `PROJECT_WORKS_DIR` 환경변수가 설정되어 있는지 확인한다.

```bash
echo $PROJECT_DRIVE_PATH
echo $PROJECT_WORKS_DIR
```

**환경변수가 없는 경우:**
사용자에게 `/setting` 실행을 안내하고 종료한다:

```
PROJECT_DRIVE_PATH 또는 PROJECT_WORKS_DIR가 설정되지 않았습니다.
/setting 을 먼저 실행해 Google Drive 경로를 설정해 주세요.
```

**환경변수가 있는 경우:**
Feature ID 파일 경로를 구성한 뒤 존재 여부를 확인한다:

```bash
WORKS_PATH="$PROJECT_DRIVE_PATH/$PROJECT_WORKS_DIR"
ls "$WORKS_PATH/[feature-id].md"
```

파일이 없으면 사용자에게 알리고, 명세서를 직접 붙여넣을지 묻는다.
파일이 있으면 Read 툴로 해당 파일을 읽는다.

### Step 3 — 베이스 브랜치 생성

```bash
git checkout dev
git pull origin dev
git checkout -b feature/[feature-id]/base
git push -u origin feature/[feature-id]/base
```

### Step 4 — 명세서 분석 및 task 파일 자동 생성

읽어온 문서를 분석해 작업을 독립적인 단위로 분리한다.

**분리 기준:**
- 하나의 task는 단일 관심사를 다룬다 (컴포넌트 1개, 기능 1개, 설정 1개 등)
- task 간 의존성이 있으면 phase 번호로 순서를 표현한다
- 너무 작은 변경(1~2줄)은 인접한 task에 합친다

**파일명 규칙:** `phase-N-[task-slug].md` (kebab-case, 한글 허용)

각 파일은 `.claude/tasks/TEMPLATE.md` 구조를 따라 작성한다.

task 파일 생성 후 base 브랜치에 커밋한다:

```bash
git add .claude/tasks/
git commit -m "chore: add task files for [feature-id]"
git push
```

### Step 5 — 완료 안내

```
✅ feature/[feature-id]/base 브랜치 생성 완료
✅ task 파일 N개 생성:
   - phase-1-[task].md
   - phase-2-[task].md
   ...

/harness 를 실행하면 순서대로 작업이 진행됩니다.
```

---

## Tools You Can Use

- **AskUserQuestion** - Feature ID 입력받기, 폴백 명세서 입력받기
- **Bash** - 환경변수 확인, git 명령어, 파일 목록 확인
- **Read** - Obsidian md 파일 읽기
- **Write** - task md 파일 생성

---

## Example Execution

```
User: /work

[WORK] Feature ID를 알려주세요. → ABC-123

echo $PROJECT_DRIVE_PATH
→ /Users/neo/Library/CloudStorage/GoogleDrive-neo@partnerble.com/My Drive/Partnerble
echo $PROJECT_WORKS_DIR
→ dev/org/partnerble/partnerble-frontend/works

WORKS_PATH="$PROJECT_DRIVE_PATH/$PROJECT_WORKS_DIR"
ls "$WORKS_PATH/ABC-123.md"
→ /Users/neo/Library/CloudStorage/.../Partnerble/dev/org/partnerble/partnerble-frontend/works/ABC-123.md

[Read ABC-123.md]
[명세서 분석 → 3개 task로 분리]

git checkout main && git pull origin main
git checkout -b feature/ABC-123/base
git push -u origin feature/ABC-123/base

.claude/tasks/phase-1-헤더_CTA_버튼.md 생성
.claude/tasks/phase-2-모바일_플로팅_버튼.md 생성
.claude/tasks/phase-3-business_리다이렉트.md 생성

git add .claude/tasks/ && git commit -m "chore: add task files for ABC-123" && git push

✅ feature/ABC-123/base 브랜치 생성 완료
✅ task 파일 3개 생성 완료

/harness 를 실행하면 순서대로 작업이 진행됩니다.
```

---

## Important Notes

- `PROJECT_DRIVE_PATH` / `PROJECT_WORKS_DIR`는 `.claude/settings.local.json`의 `env`에 설정 (gitignored)
- 설정되지 않은 경우 `/setting` 실행을 안내하고 종료한다
- 경로 탐색 기준: `$PROJECT_DRIVE_PATH/$PROJECT_WORKS_DIR/[feature-id].md` 단일 파일 (디렉터리 아님)
- 문서가 없으면 AskUserQuestion으로 명세서를 직접 붙여넣는 폴백 제공
- base 브랜치에 코드를 직접 커밋하지 않는다 — task 파일 커밋만 허용
- `/work` 완료 후 반드시 `/harness` 로 이어진다
- **⛔ 절대 금지**: 에이전트는 어떠한 경우에도 `main` 브랜치에 push하거나 머지할 수 없다. `main` 관련 작업은 관리자 전용이다.
