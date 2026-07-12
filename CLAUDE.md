# CLAUDE.md — semi:bold iOS App Rules

This file is always referenced by Claude Code. Rules here apply
automatically in every conversation about this project.

semi:bold is a local-first, block-based document app (Folder → Document →
Block) built with SwiftUI. Product spec and visual design live in
separate repos, **not** here — read them before writing or changing any
screen, flow, or data model. Do not duplicate their content into this
file; they change independently of Swift coding conventions.

---

## 0. Source of Truth — Read Before Touching Screens, Flows, or Data Models

```
semi-bold/
 ├─ semibold-ios/        ← this repo (Swift app)
 ├─ semibold-docs/       ← planning docs (task specs, PLANNING.md, SERVICE.md)
 │   ├─ tasks/<work-code>.md ← per-work-code task spec (primary —
 │   │             read first for the work code `/work` assigned)
 │   ├─ PLANNING.md  ← legacy: feature scope, screens, flows, DB
 │   │                  schema (fallback for anything tasks/* doesn't cover)
 │   └─ SERVICE.md   ← access policy, data structure
 └─ Figma             ← wireframes & design tokens (read via Figma MCP)
     Frame "Screen_<Name>"          → SwiftUI view "<Name>View"
     Frame "Planning_<n>_<FlowName>" → flow spec with callout badges
     Variables (color/spacing/type) → AppTheme.swift design tokens
```

Relative to this repo: `../semibold-docs/tasks/<work-code>.md`,
`../semibold-docs/PLANNING.md`, and `../semibold-docs/SERVICE.md`.

Before implementing or changing a screen/flow/model:

1. Read `../semibold-docs/tasks/<work-code>.md` for the work code
   `/work` assigned to this batch of `.claude/features/` briefs (see
   `.claude/skills/work/SKILL.md`), if it exists — it's the primary,
   current spec. Fall back to the relevant section of `PLANNING.md`
   (legacy — screen structure, user flows, feature requirements,
   block/markdown model, DB schema) for anything `tasks/*` doesn't cover.
   Always read `SERVICE.md` for current, authoritative data structure
   details — don't rely on a cached summary.
2. Check whether a matching frame (`Screen_*` / `Planning_N_*`) exists in
   Figma (see §1) and build to match it rather than inventing a different
   layout or flow.
3. If a request conflicts with these docs, or no matching frame/spec
   exists yet, say so explicitly rather than improvising silently.

**Feature briefs (`.claude/features/`).** Before starting non-trivial work
on a feature, write a brief to `.claude/features/<slug>.md` (copy
`.claude/features/TEMPLATE.md`) that records: which `Screen_*` /
`Planning_N_*Flow` / `tasks/<work-code>.md` (or legacy `PLANNING.md`)
sections it maps to, scope/out-of-scope, any decisions or deviations from
the docs, and acceptance criteria. This is the working record for the
current batch of work — anyone (or any agent, on any machine) picking up
the implementation should read this brief first, then
`tasks/<work-code>.md`/`PLANNING.md`/`SERVICE.md`/wireframes for design
and data details it doesn't restate. Briefs are deleted once the whole
batch is `done` (see `.claude/skills/work/SKILL.md` Completion) — git
history retains their content for reference.

If a brief has prerequisites (must come after another brief), prefix its
filename with a two-digit order number (`01-`, `02-`, …) matching the
phase order in `tasks/<work-code>.md` (or, for legacy phases,
`PLANNING.md` §18), so the build order is clear from the directory
listing alone. Briefs without ordering dependencies (e.g. tooling work)
don't need a prefix.

---

## 1. Mapping Figma Frames & Planning Specs to SwiftUI Screens

Figma is the design source of truth. Implementation should trace back
to Figma frames 1:1 by name:

```
Figma frame "Screen_<Name>"              → SwiftUI view "<Name>View"
Figma frame "Planning_<n>_<FlowName>"   → flow described in tasks/<work-code>.md
                                            (or legacy PLANNING.md §5),
                                            numbered to match its callouts
Figma Variables (color/spacing/type)    → AppTheme.swift tokens
```

- `Screen_*` frames are the literal layout reference — match element
  placement, hierarchy, and sizing using the iPhone canvas (390×844)
  as the design baseline.
- `Planning_N_*` frames embed numbered callout badges (①②③…) with a
  UI/UX-perspective description list and a `mermaid` flow diagram. Treat
  each callout as a concrete UI element/state to produce in order.
  They deliberately omit storage details — get the data model from
  `tasks/<work-code>.md` (or legacy `PLANNING.md` §6/§9) instead.

Keep SwiftUI view/type names aligned with these frame names so anyone
can jump between Figma and the codebase.

**Read the design via Figma MCP.** Use the Figma MCP server to inspect
frame structure, component layout, and Variable values directly — do not
rely on cached descriptions. Color/spacing/typography values from Figma
Variables map to `AppTheme.swift` tokens (see §2 and §3).

### Figma MCP — 설치 및 사용 방법

#### 설치 (처음 설정하는 경우)

**방법 1 — 공식 Claude Code 플러그인 (권장):**
```bash
claude plugin install figma@claude-plugins-official
```
설치 후 Claude Code 내에서 `/plugin` 또는 `/mcp` 명령으로 Figma 인증을
완료하고 연결 상태를 확인한다.

**방법 2 — 원격 MCP 서버 (플러그인이 동작하지 않을 경우 대안):**
```bash
# 프로젝트 범위
claude mcp add --transport http figma https://mcp.figma.com/mcp

# 전역 설정이 필요한 경우
claude mcp add --scope user --transport http figma https://mcp.figma.com/mcp
```

**❌ 사용 금지:** `npx @figma/mcp` 방식, `FIGMA_API_KEY`를 `~/.claude.json`에
평문 저장하는 방식은 사용하지 않는다.

#### 연결 확인 테스트

설치 후 아래 프롬프트로 동작을 검증한다 (`<Figma 링크>`는 프로젝트 오너에게
문의하거나 세션 시작 시 직접 붙여넣는다 — URL/파일키는 git에 커밋하지 않는다):
```
Use the Figma MCP server.
Open this Figma file: <Figma 링크>
Summarize the frame structure, components, variables, and layout constraints.
Do not modify the file.
```

#### 파일 정보

**파일 키 / URL:** git에 커밋하지 않는다. 세션 시작 시 직접 제공하거나
프로젝트 오너에게 문의한다.

**페이지 구성 (node ID):**

| 페이지 | node ID |
|---|---|
| Cover | `22:2` |
| Design System | `0:1` |
| Screens | `0:556` |
| Flows | `0:1389` |

**Screens 페이지 주요 프레임:**

| 프레임 | node ID | 대응 SwiftUI |
|---|---|---|
| `Screen_Home` | `0:1003` | `HomeView` |
| `iOS_FolderContents` | `0:1163` | `FolderContentsView` |
| `Screen_Detail` | `0:1069` | `DetailView` |
| `Screen_Splash` | `26:2` | `SplashView` |
| `iOS_Onboarding` | `0:1349` | `OnboardingView` |
| `iOS_iCloudSetupRequired` | `0:1369` | `ICloudSetupRequiredView` |
| `iOS_AddMenu` | `0:1133` | add confirmation dialog |
| `iOS_HomeViewSwipe` | `0:1223` | swipe actions |

#### 조회 방법

Figma 조회는 **`use_figma` 단독으로** 처리한다. 텍스트·색상·구조·스크린샷
모두 Plugin API로 접근 가능하다.

```js
// 모든 페이지 목록
return figma.root.children.map(p => ({ id: p.id, name: p.name }))

// Screens 페이지의 최상위 프레임 목록
const page = figma.root.children.find(p => p.id === "0:556")
await figma.setCurrentPageAsync(page)
return page.children.map(n => ({ id: n.id, name: n.name }))

// 특정 프레임 스크린샷
const page = figma.root.children.find(p => p.id === "0:556")
await figma.setCurrentPageAsync(page)
const frame = page.children.find(n => n.id === "0:1003")
return await frame.screenshot()
```

---

## 2. Tech Stack

| Layer | Choice |
|---|---|
| UI | SwiftUI + `@Observable` (MVVM) |
| Local DB | Core Data (`NSPersistentContainer` / `NSPersistentCloudKitContainer`) |
| Lint | SwiftLint (SPM plugin) |
| Project generation | XcodeGen (`project.yml`) |

No additional architecture libraries. Do not introduce TCA, Combine-heavy
patterns, or a remote backend without an explicit decision to do so.

**Core Data, not GRDB.** The data layer was migrated from GRDB (SQLite)
to Core Data for work code NO-002 (iCloud sync via
`NSPersistentCloudKitContainer` — see
`../semibold-docs/tasks/NO-002.md`). This is an explicit,
already-made decision — do not reintroduce GRDB or raw `sqlite3` calls.

**`semibold.xcodeproj` is generated from `project.yml` and is not the
source of truth.** Add new targets, source groups, or SPM dependencies by
editing `project.yml`, then run `xcodegen generate` — don't hand-edit the
`.xcodeproj`. New source files just need to live under the paths
`project.yml` already references (`semibold/`); XcodeGen picks them up
automatically on the next `generate`.

---

## 3. Swift Coding Conventions

- **SwiftUI-first.** Use `@Observable` view-models. Drop to UIKit only
  where SwiftUI genuinely can't do the job (e.g. custom block-editor text
  handling).
- **Core Data** (`semibold/Data/SemiboldModel.xcdatamodeld`) owns all
  local persistence. Don't bypass it with raw `sqlite3` calls. Schema
  changes go in the versioned `.xcdatamodeld` model — never alter
  storage outside of it. Repositories (`FolderRepository`,
  `DocumentRepository`, `DocumentBlockRepository`) map `NSManagedObject`
  entities to/from the plain Swift model structs so the rest of the app
  never touches Core Data types directly.
- Name Swift model types/fields after the DB schema in
  `tasks/<work-code>.md` (or legacy `PLANNING.md` §9) (`sortOrder`,
  `parentId`, `contentJSON`, `markdownSource`, …) so the data layer maps
  directly onto it — don't invent parallel naming.
- Centralize colors/spacing/typography in one `AppTheme` type rather than
  hardcoding values in views — mirrors Figma Variables on the design side,
  and keeps both in sync when the palette changes.
- Keep core models/view-models shared across iOS and macOS targets; let
  only navigation chrome and input affordances diverge per platform.
- Keep functional/UX explanations (comments, PR text) at a planner's
  altitude — what the user sees and why. Reserve DB/storage vocabulary
  (`content_json`, `sort_order`, `deleted_at`, …) for the data layer.

---

## 4. README Constraints

README is for project-wide build/setup information only.

**Include in README:**
- Xcode / Swift / deployment target requirements
- How to clone and open in Xcode
- SPM dependency resolution note
- SwiftLint setup (if any manual step is needed beyond SPM)

**Never put in README:**
- Service description, feature list, or product scope
- Directory/file structure
- Planning details or current implementation phase
- Environment variables, API keys, or any credentials
- Anything that changes at the module/feature level

Items that belong in CLAUDE.md (like the constraints above), not README.

---

## 5. What You Can Ask Claude

```
"Implement the folder list screen to match the Screen_Home frame in Figma"
"Build the folder-create flow per Planning_2_FolderCreateFlow / PLANNING §5.2"
"Add support for the <X> block type per PLANNING §7–8"
```

---

## Reference

- Per-work-code task spec (primary): `../semibold-docs/tasks/<work-code>.md`
- Planning & data model (legacy fallback): `../semibold-docs/PLANNING.md`
- Service / access-policy structure: `../semibold-docs/SERVICE.md`
- Wireframes & design tokens: Figma (read via Figma MCP)
  — frame names `Screen_*` / `Planning_N_*`, Variables → `AppTheme.swift`
