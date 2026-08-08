# Feature: 03-sidebar-drawer

## Source

- `tasks/NO-008.md` §2.1, §3.2 (검색 중심으로 재편한 이유)
- Figma: `Planning_Nav_2_DrawerFlow` (FLOW-NAV-002) — `iOS_SidebarDrawer` (default: search bar + 계정 row, nothing else) and `iOS_SidebarDrawer_Search` (results: folder/document rows, each with an icon — `Icon_Folder`/`Icon_Doc`, reused from the existing folder/document row icons — and, for documents, the parent folder name in a smaller secondary line below the title).

## Scope

- In scope:
  - A new drawer view presented from the menu icon's state toggle (wired in `02-topbar-fab-menu-icon`), sliding in from the left over a dimmed background, matching the Figma `DimOverlay` treatment.
  - Default (no keyword typed) state: just the search bar and the account row at the bottom — no folder list, no "모든 문서"/"최근 문서" (explicitly removed per NO-008 §3.2).
  - Search-active state: as the user types, show matching folders and documents (via `01-cross-folder-search`'s repository methods) as a flat list — folder rows use the existing folder icon, document rows use the existing document icon plus the parent folder name in secondary text below the title.
  - Tapping a document result navigates to that document (`DetailView`); tapping a folder result navigates into that folder (`FolderContentsView`). Both should close the drawer first.
  - The account row at the bottom is a tappable row (icon + "계정" label) — wire its tap to open the tooltip menu built in `04-account-tooltip-and-alerts`; this brief only needs to expose the tap target/hook, not the tooltip itself.
- Out of scope / deferred:
  - The account tooltip/alert flow itself (`04-account-tooltip-and-alerts`).
  - The actual search query logic (`01-cross-folder-search` — depend on it, don't reimplement it).

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `iOS_SidebarDrawer` / `iOS_SidebarDrawer_Search` (`Planning_Nav_2_DrawerFlow`, FLOW-NAV-002) | new `SidebarDrawerView` (naming implementer's call) | Presented from `HomeView`/`FolderContentsView`/`DetailView` via the state toggle from `02-topbar-fab-menu-icon` |

## Decisions & Deviations

- SwiftUI has no built-in "drawer" component — this needs a custom overlay (e.g. a `ZStack` with a dimming `Color.black.opacity(...)` layer + an offset/animated drawer panel, or `.sheet`/`.fullScreenCover` styled to look like a drawer). Pick whichever is simplest to get right; note the choice here isn't specified by the Figma mockup (which only shows the end state, not the transition mechanics) — flag as an Open Question if genuinely ambiguous.
- Reuse the existing folder/document row icons (the ones `HomeView`/`FolderContentsView` already use for their own list rows) rather than drawing new ones — the Figma mockup explicitly cloned those existing icons rather than fabricating new ones, and the code should follow the same reuse.
- Debounce the search-as-you-type calls to `01-cross-folder-search`'s methods (matching the app's existing debounce convention for text-driven work, e.g. `DetailViewModel`'s autosave debounce) rather than querying on every keystroke.

## Acceptance Criteria

- [ ] Toggling the menu icon (from `02-topbar-fab-menu-icon`) on `HomeView`, `FolderContentsView`, and `DetailView` presents this drawer, sliding in from the left with a dimmed background.
- [ ] With no search keyword typed, the drawer shows only the search bar and the account row — no folder shortcuts, no "모든 문서"/"최근 문서".
- [ ] Typing a keyword shows matching folders and documents in one list; folder rows show a folder icon, document rows show a document icon plus the parent folder's name beneath the title.
- [ ] Tapping a document result closes the drawer and navigates to that document; tapping a folder result closes the drawer and navigates to that folder.
- [ ] The account row is present at the bottom in both the default and search-active states and is tappable (hook only — no behavior required yet from this brief).
- [ ] Works from all three entry screens (`HomeView`, `FolderContentsView`, `DetailView`).

## Open Questions / Follow-ups

- Confirm the preferred drawer-presentation mechanism (custom overlay vs. styled sheet) if the implementer's default choice looks or feels wrong compared to the Figma mockup.
- Confirm debounce interval for the live search (no value specified in the spec — match `DetailViewModel`'s existing default unless there's a reason to differ).
