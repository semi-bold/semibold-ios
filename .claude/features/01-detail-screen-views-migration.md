# Feature: 01-detail-screen-views-migration

## Source

- `tasks/NO-007.md` §2 (Views 구조 개편과의 연결, 2026-08-13 논의)
- Precedent: `feature/NO-008`'s NavBar-layout-extraction work, and the
  earlier Views 1차 구조 개편 (Home/FolderContents → Screens/Layouts/
  Components) — same repo, same session, no separate tasks/ doc (a direct
  refactor, not a NO-XXX-numbered feature).

## Scope

- In scope:
  - `git mv semibold/Views/Detail/DetailView.swift semibold/Views/Screens/Detail/DetailScreen.swift`
  - Rename `struct DetailView: View` → `struct DetailScreen: View` inside
    that file.
  - Update the two real call sites: `HomeScreen.swift`'s
    `.navigationDestination(for: Document.self) { DetailScreen(document: document) }`
    (currently `DetailView(document:)`), and `DetailScreen`'s own
    `#Preview`.
  - Sweep doc-comment prose mentions of "`DetailView`" elsewhere in the
    codebase to say "`DetailScreen`" instead (matches the sweep already
    done for `HomeView`→`HomeScreen`/`FolderContentsView`→
    `FolderContentsScreen` — word-boundary-safe replace, not touching
    `DetailViewModel` — see Decisions).
  - `SlashCommandSheet.swift` stays in `Views/Detail/` for this brief —
    see Open Questions.
- Out of scope / deferred:
  - Splitting `BlockRow` into per-kind components — `02-block-row-shared-chrome`/
    `03-divider-block-split`.
  - Any behavior change. This brief is a pure move + rename — if a build
    or test result differs from before this brief, that's a bug in this
    brief, not an intentional change.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `iOS_Editor` (wireframe) | `DetailScreen` (renamed from `DetailView`) | No visual/behavioral change |

## Decisions & Deviations

- **Do this move first, before either BlockRow-splitting brief** — the
  block-splitting briefs create brand-new per-kind view files, and they
  should land directly in their final `Views/Components/Block/` location
  rather than being created in the old `Views/Detail/` and moved again
  later (`tasks/NO-007.md` §2's core rationale).
- **`DetailViewModel` and its extension files are NOT renamed** — only
  the View struct (`DetailView` → `DetailScreen`) and its file move. The
  ViewModel naming convention (`<Name>ViewModel`) is independent of the
  View naming convention (`<Name>Screen`) — `HomeViewModel`/
  `FolderContentsViewModel` were likewise left untouched when
  `HomeView`/`FolderContentsView` became `HomeScreen`/`FolderContentsScreen`.
  Don't rename `DetailViewModel` → `DetailScreenModel` or similar.
- Follow the exact word-boundary-safe sweep approach used for the
  `HomeView`→`HomeScreen` rename: `grep -rl -E "\bDetailView\b"`, then a
  per-file `perl -i -pe 's/\bDetailView\b/DetailScreen/g'` loop (protects
  `DetailViewModel` automatically, since `\b` won't match between
  `DetailView` and `Model`).

## Acceptance Criteria

- [ ] `semibold/Views/Detail/DetailView.swift` no longer exists;
      `semibold/Views/Screens/Detail/DetailScreen.swift` exists with
      identical content except the renamed struct.
- [ ] `struct DetailScreen: View` (renamed from `DetailView`) — same
      `init`, same `body`, same private members, byte-for-byte behavior.
- [ ] `HomeScreen.swift`'s `.navigationDestination(for: Document.self)`
      constructs `DetailScreen(document:)`.
- [ ] No remaining `\bDetailView\b` references anywhere in `semibold/`/
      `semiboldTests/` (word-boundary check — `DetailViewModel` is
      unaffected and must NOT be touched).
- [ ] `xcodegen generate` re-run, project builds clean
      (`xcodebuild build`), full test suite passes (existing flaky
      `CoreDataTestStore` cross-suite tests aside — rerun to confirm
      unrelated if any single test fails).

## Open Questions / Follow-ups

- `SlashCommandSheet.swift` currently lives in `Views/Detail/` alongside
  `DetailView.swift`. Should it move to `Views/Screens/Detail/` too (as a
  screen-scoped sheet, following `NewFolderSheet`/`RenameFolderSheet`'s
  precedent of living in `Views/Components/FolderManagement/`), or does
  it stay put since this brief's Scope is deliberately narrow (just the
  screen file itself)? Recommend leaving `Views/Detail/` as a folder
  containing just `SlashCommandSheet.swift` after this brief, and letting
  `swift-reviewer`/a human flag if that's an insufficient number of files
  to justify keeping the folder — not blocking for this brief either way.
