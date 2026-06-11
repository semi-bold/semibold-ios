# CLAUDE.md — semi:bold iOS App Rules

This file is always referenced by Claude Code. Rules here apply
automatically in every conversation about this project.

semi:bold is a local-first, block-based document app (Folder → Document →
Block) built with SwiftUI. Product spec and visual design live in a
sibling repo, **not** here — read them before writing or changing any
screen, flow, or data model. Do not duplicate their content into this
file; they change independently of Swift coding conventions.

---

## 0. Source of Truth — Read Before Touching Screens, Flows, or Data Models

```
semi-bold/
 ├─ semibold-ios/        ← this repo (Swift app)
 └─ sketch-autokit/      ← planning docs + Sketch wireframe generator
     ├─ docs/
     │   ├─ tasks/<work-code>.md ← per-work-code task spec (primary —
     │   │             read first for the work code `/work` assigned)
     │   ├─ PLANNING.md  ← legacy: feature scope, screens, flows, DB
     │   │                  schema (fallback for anything tasks/* doesn't
     │   │                  cover)
     │   └─ SERVICE.md   ← Private/Secret/Public structure, access policy
     └─ semi-bold.sketch ← generated wireframes & planning specs
         (screens/wireframe.py → Screen_*, screens/planning.py → Planning_N_*Flow)
```

Relative to this repo: `../sketch-autokit/docs/tasks/<work-code>.md`,
`../sketch-autokit/docs/PLANNING.md`, and
`../sketch-autokit/docs/SERVICE.md`.

Before implementing or changing a screen/flow/model:

1. Read `../sketch-autokit/docs/tasks/<work-code>.md` for the work code
   `/work` assigned to this batch of `.claude/features/` briefs (see
   `.claude/skills/work/SKILL.md`), if it exists — it's the primary,
   current spec. Fall back to the relevant section of `PLANNING.md`
   (legacy — screen structure, user flows, feature requirements,
   block/markdown model, DB schema) for anything `tasks/*` doesn't cover.
   Always read `SERVICE.md` (Private/Secret/Public scope and access
   policy) for current, authoritative details — don't rely on a cached
   summary.
2. Check whether a matching wireframe or planning spec already exists in
   `sketch-autokit` (see §1) and build to match it rather than inventing
   a different layout or flow.
3. If a request conflicts with these docs, or no matching wireframe/spec
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

## 1. Mapping Wireframes & Planning Specs to SwiftUI Screens

`sketch-autokit` generates two kinds of artifacts in `semi-bold.sketch`,
and the implementation should trace back to them 1:1 by name:

```
Wireframe artboard "Screen_<Name>"            → SwiftUI view "<Name>View"
Planning doc "Planning_<n>_<FlowName>"        → flow described in tasks/<work-code>.md
                                                 (or legacy PLANNING.md §5),
                                                 numbered to match its callouts
```

- Wireframes (`screens/wireframe.py`, `Screen_*`) are the literal layout
  reference — match element placement/hierarchy/sizing, using the same
  iPhone canvas (390×844) as the design baseline.
- Planning specs (`screens/planning.py`, `Planning_<n>_*Flow`) embed
  numbered callout badges (①②③…) with a matching UI/UX-perspective
  description list and a `mermaid` flow diagram. Treat each callout as a
  concrete UI element/state to produce in order, and the diagram as the
  state machine your view/view-model implements. They deliberately omit
  storage details — get the data model from `tasks/<work-code>.md` (or
  legacy `PLANNING.md` §6/§9) instead.

Keep SwiftUI view/type names aligned with these artifact names so anyone
can jump between the Sketch file and the codebase.

**Read the design from the Python source, not the `.sketch` binary.**
`screens/wireframe.py`, `screens/planning.py`, `components/atoms.py`, and
`sketch/tokens.py` declare every layer's exact position, size, color
token, and text — they're the actual design source (the `.sketch` file is
just generated output from them, and rendering it requires the Sketch
macOS app, which Claude can't do). Reconstruct the layout pixel-for-pixel
from these files: component structure from `atoms.py`, layout/composition
from `wireframe.py`/`planning.py`, and color/spacing/type values from
`tokens.py` — then translate those same values into the SwiftUI view and
its design-tokens type (see §2).

---

## 2. Tech Stack

| Layer | Choice |
|---|---|
| UI | SwiftUI + `@Observable` (MVVM) |
| Local DB | GRDB.swift (SQLite) |
| Lint | SwiftLint (SPM plugin) |
| Project generation | XcodeGen (`project.yml`) |

No additional architecture libraries. Do not introduce Core Data, TCA,
Combine-heavy patterns, or a remote backend without an explicit decision
to do so.

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
- **GRDB** owns all SQLite access. Don't bypass it with raw
  `sqlite3` C calls. Migrations go in a versioned `DatabaseMigrator`
  block — never alter the schema outside of migrations.
- Name Swift model types/fields after the DB schema in
  `tasks/<work-code>.md` (or legacy `PLANNING.md` §9) (`sortOrder`,
  `parentId`, `contentJSON`, `markdownSource`, …) so the data layer maps
  directly onto it — don't invent parallel naming.
- Centralize colors/spacing/typography in one `AppTheme` type rather than
  hardcoding values in views — mirrors the `sketch/tokens.py` rule on the
  design side, and keeps both in sync when the palette changes.
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
"Implement the folder list screen to match Screen_Home in the wireframe"
"Build the folder-create flow per Planning_2_FolderCreateFlow / PLANNING §5.2"
"Add support for the <X> block type per PLANNING §7–8"
```

---

## Reference

- Per-work-code task spec (primary): `../sketch-autokit/docs/tasks/<work-code>.md`
- Planning & data model (legacy fallback): `../sketch-autokit/docs/PLANNING.md`
- Service / access-policy structure: `../sketch-autokit/docs/SERVICE.md`
- Wireframes & planning specs: `../sketch-autokit/semi-bold.sketch`
  (`screens/wireframe.py`, `screens/planning.py`)
