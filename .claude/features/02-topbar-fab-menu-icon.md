# Feature: 02-topbar-fab-menu-icon

## Source

- `tasks/NO-008.md` §2.1, §3.1 (`+`를 플로팅 버튼으로 옮긴 이유)
- Figma: `Planning_Nav_1_TopBarFlow` (FLOW-NAV-001) — `icon_menu` (hamburger) added to the NavBar's trailing corner across `iOS_PrivateSpace`/`iOS_FolderContents`/`iOS_Editor`; the `+` button moved to a floating circular button at the bottom-right (`FAB_AddMenu`: accent-filled circle, white plus glyph, drop shadow).

## Scope

- In scope:
  - `HomeView`, `FolderContentsView`: remove `addButton` (the inline "+" in the custom NavBar) and `switchAccountButton` (the account icon in the NavBar) — both move out of the top bar per this redesign (account handling moves into the new drawer, built in `04-account-tooltip-and-alerts`).
  - Add a menu icon button (hamburger) in the NavBar's trailing position on `HomeView`, `FolderContentsView`, and `DetailView` (`DetailView`'s NavBar currently only has the back chevron — this is a new addition there, not a replacement).
  - The menu icon toggles a `@State` boolean (e.g. `isDrawerPresented`) — wire the toggle only; the drawer's actual content is built in `03-sidebar-drawer`, so for this brief presenting `EmptyView()` (or leaving the presentation call commented with a `// TODO(03-sidebar-drawer)`) is fine as long as the state and the tap target exist and are testable.
  - Add a floating circular "+" button (FAB) anchored to the bottom-trailing corner of `HomeView` and `FolderContentsView`, above the safe area, calling the same `isAddMenuPresented = true` these views already use — the existing `.confirmationDialog("Add", ...)` menu itself does not change.
- Out of scope / deferred:
  - The drawer's content (`03-sidebar-drawer`).
  - Where the account button's behavior goes (`04-account-tooltip-and-alerts`) — just remove it from the NavBar here.
  - `iOS_AddMenu`'s Figma "active" FAB state (the semi-transparent tinted circle shown while the add-menu sheet is open) — that's a visual nicety the existing `AddButtonStyle`'s press-state tinting already approximates; no separate state needed unless it looks wrong once built.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `Planning_Nav_1_TopBarFlow` (FLOW-NAV-001) | `HomeView`, `FolderContentsView` | NavBar restructure + new FAB |
| `Planning_Nav_1_TopBarFlow` (FLOW-NAV-001) | `DetailView` | Add menu icon only (no FAB — Editor has no "add" concept) |

## Decisions & Deviations

- Reuse the existing shared `AddButton` (`Views/Shared/AddButton.swift`) for the FAB rather than building a new button component — but per the Figma mockup the FAB should read as a permanently accent-filled circle with a drop shadow (not `AddButton`'s current "only tinted while pressed, otherwise plain" style). Either extend `AddButton` with a style variant/parameter, or confirm with `swift-reviewer`/the user whether a dedicated `FloatingAddButton` is cleaner — don't silently duplicate the plus-glyph logic if it can be shared.
- The menu icon needs a new icon asset — check `Assets.xcassets` for an existing Material-Symbols-style menu/hamburger icon (matching `IconHome.svg`'s convention) before drawing one from scratch; if none exists, flag it as an Open Question rather than fabricating one (this codebase has been burned by fabricated icons before — ask first).
- `DetailView`'s NavBar padding/layout may need adjusting now that it has a trailing element for the first time (previously just the leading chevron) — match the same trailing inset `HomeView`/`FolderContentsView` use for consistency.

## Acceptance Criteria

- [ ] `HomeView` and `FolderContentsView` no longer show a "+" or account icon in their top NavBar.
- [ ] `HomeView`, `FolderContentsView`, and `DetailView` each show a menu (hamburger) icon in the NavBar's trailing position, wired to a state toggle.
- [ ] `HomeView` and `FolderContentsView` each show a floating "+" button at the bottom-trailing corner, positioned clear of the safe area / any bottom chrome, that opens the same existing "New Folder / New Document" menu as before.
- [ ] Tapping the floating "+" and the existing confirmation dialog behavior (New Folder / New Document / Cancel) is unchanged from today.
- [ ] Existing tests referencing `addButton`/`switchAccountButton` in these views are updated to match the new structure (don't leave stale references).

## Open Questions / Follow-ups

- Does an existing menu/hamburger icon asset exist anywhere in `Assets.xcassets`? If not, ask the user before adding a new one (see Decisions above).
- Confirm whether `AddButton` should gain a "permanently filled" style variant for the FAB, or whether a separate small `FloatingAddButton` view is preferred.
