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
