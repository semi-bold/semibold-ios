---
name: release
description: Mark a release version in package.json and README from a production PR link, then push to dev
---

You are the release version manager for Partnerble.

When the user runs `/release`, you:
1. Ask for the production PR link (`dev → main`)
2. Read the PR title to extract the version
3. Check out `dev` and pull latest
4. Update `package.json` and `README.md` with the version
5. Commit and push to `dev`
6. Guide the user on remaining steps

---

## Workflow

### Step 1 — PR 링크 요청

AskUserQuestion 툴로 상용 PR 링크를 입력받는다.

```
dev → main PR 링크를 공유해 주세요.
(예: https://github.com/org/repo/pull/3)
```

### Step 2 — PR에서 버전 추출

입력된 URL에서 PR 번호를 파싱한 뒤 `gh pr view`로 제목을 읽는다:

```bash
gh pr view {pr_number} --json title,baseRefName,headRefName
```

- base가 `main`이고 head가 `dev`인지 확인한다. 아니면 사용자에게 알리고 종료.
- 제목에서 버전 문자열을 추출한다.
  - 예: `"Release(v0.1.1)"` → `v0.1.1` / `0.1.1`
  - 예: `"v0.2.0"` → `v0.2.0` / `0.2.0`
  - 버전 패턴: `v?(\d+\.\d+\.\d+)`

### Step 3 — dev 브랜치 최신화

```bash
git checkout dev
git pull origin dev
```

### Step 4 — 버전 업데이트

#### 4-1. `package.json`

`"version"` 필드를 추출한 버전(숫자만, `v` 접두사 제외)으로 교체한다.

```json
"version": "0.1.1"
```

Read 툴로 파일을 읽고 Edit 툴로 정확히 교체한다.

#### 4-2. `README.md`

파일 최상단(첫 줄 `# Partnerble` 바로 아래)에 버전 배지 라인을 추가하거나 기존 배지를 교체한다.

```markdown
# Partnerble

![version](https://img.shields.io/badge/version-v0.1.1-blue)
```

- 이미 `![version](...)` 배지가 있으면 버전 숫자만 교체한다.
- 없으면 `# Partnerble` 바로 아래 빈 줄 뒤에 추가한다.

### Step 5 — 커밋 및 push

```bash
git add package.json README.md
git commit -m "chore: release v0.1.1"
git push origin dev
```

### Step 6 — 이후 작업 안내

```
✅ v0.1.1 버전 표기 완료 (dev 브랜치 반영)

이제 아래 순서로 진행해 주세요:

1. GitHub에서 PR #{number} 머지 (dev → main)
2. main 브랜치 로컬 최신화 후 태그 생성:
   git checkout main && git pull origin main
   git tag -a v0.1.1 -m "Release v0.1.1"
   git push origin v0.1.1
3. GitHub Release 생성:
   gh release create v0.1.1 --title "v0.1.1" --target main --generate-notes
```

---

## Tools You Can Use

- **AskUserQuestion** — PR 링크 입력받기
- **Bash** — `gh pr view`, git 명령어
- **Read** — `package.json`, `README.md` 읽기
- **Edit** — 버전 교체

---

## Example Execution

```
User: /release

[RELEASE] PR 링크를 공유해 주세요. → https://github.com/org/repo/pull/3

gh pr view 3 --json title,baseRefName,headRefName
→ title: "Release(v0.1.1)", base: "main", head: "dev"
→ 버전 추출: v0.1.1 / 0.1.1

git checkout dev && git pull origin dev

[package.json] "version": "0.1.0" → "0.1.1"
[README.md] 배지 추가: ![version](...-v0.1.1-blue)

git add package.json README.md
git commit -m "chore: release v0.1.1"
git push origin dev

✅ v0.1.1 버전 표기 완료

이후 작업:
1. PR #3 머지 (dev → main)
2. git tag -a v0.1.1 ...
3. gh release create v0.1.1 ...
```

---

## Important Notes

- 반드시 `dev` 브랜치에서만 작업한다 — `main`에 직접 커밋하지 않는다
- `package.json`의 버전은 `v` 접두사 없이 숫자만 (`0.1.1`)
- `README.md`의 배지는 `v` 접두사 포함 (`v0.1.1`)
- PR의 base가 `main`이 아니거나 head가 `dev`가 아니면 실행을 중단하고 사용자에게 알린다
- **⛔ 절대 금지**: `main` 브랜치에 push하거나 머지하지 않는다