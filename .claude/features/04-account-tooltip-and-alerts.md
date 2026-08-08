# Feature: 04-account-tooltip-and-alerts

## Source

- `tasks/NO-008.md` §1.1 (탈퇴 기능 부재 — Apple 심사 가이드라인 5.1.1(v)), §2.1, §3.3 (커스텀 팝업으로 바꾼 이유)
- Figma: `Planning_Nav_3_AccountFlow` (FLOW-NAV-003) — `iOS_SidebarDrawer_AccountMenu` (compact tooltip above the account row: "로그아웃" emphasized red, "탈퇴하기" gray/smaller, with a small pointer triangle), `iOS_SidebarDrawer_LogoutAlert` and `iOS_SidebarDrawer_DeleteAccountAlert` (centered iOS-alert-style popups, title + message + Cancel/Confirm buttons attached in one card).

## Scope

- In scope:
  - Tapping the drawer's account row (from `03-sidebar-drawer`) shows a compact tooltip menu anchored above it, with two options: "로그아웃" (destructive-red, normal emphasis) and "탈퇴하기" (secondary gray, smaller text — intentionally de-emphasized at this step).
  - Tapping "로그아웃" in the tooltip shows a centered alert-style popup reproducing the *exact* existing copy from `HomeView.switchAccountButton`'s current `.confirmationDialog` (title "로그아웃", the same message text, "취소"/"로그아웃" buttons) — just restyled as a custom centered card instead of a system action sheet.
  - Tapping "탈퇴하기" in the tooltip shows a second centered alert-style popup with new, stronger copy: title "계정을 탈퇴할까요?", message covering permanent deletion of the account and all iCloud-stored documents/folders, irreversibility — "취소"/"탈퇴하기" buttons.
  - Confirming "로그아웃" calls the same reset-to-onboarding path `HomeView`'s existing button already triggers (`onResetToOnboarding`) — no behavior change there, just relocated.
  - Confirming "탈퇴하기" calls a new callback (e.g. `onDeleteAccount`) — implementing what that callback actually *does* (deleting data) is `05-account-deletion`; this brief only needs the callback to exist and be wired, e.g. to a stub/TODO if `05` hasn't landed yet.
  - Remove `HomeView.switchAccountButton` and its `.confirmationDialog` entirely — this flow replaces it (already partly done by removing it from the NavBar in `02-topbar-fab-menu-icon`; this brief removes the now-dead confirmation-dialog code too).

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `iOS_SidebarDrawer_AccountMenu` (FLOW-NAV-003) | tooltip view, anchored to the drawer's account row | |
| `iOS_SidebarDrawer_LogoutAlert` (FLOW-NAV-003) | custom alert view | Reuses existing logout copy verbatim |
| `iOS_SidebarDrawer_DeleteAccountAlert` (FLOW-NAV-003) | custom alert view | New copy — see Decisions |

## Decisions & Deviations

- This deliberately does **not** use SwiftUI's native `.confirmationDialog`/`.alert` for either popup — see `tasks/NO-008.md` §3.3 for why (keeping "탈퇴하기" out of the same one-tap action sheet as "로그아웃"). Build a small reusable "centered alert card" view (title + message + two attached buttons) since both popups share the same visual shape — don't duplicate the card chrome between the two.
- Delete-account message copy (from the Figma mockup, use verbatim unless the user wants it reworded): "탈퇴하면 이 계정과 iCloud에 저장된 모든 문서·폴더가 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없습니다."
- The tooltip's "탈퇴하기" entry is intentionally styled smaller and gray (not destructive-red) — the red, high-emphasis treatment is reserved for the second-step alert only. Don't "fix" this by making both red; it's a deliberate two-tier emphasis decision from the Figma mockup.

## Acceptance Criteria

- [ ] Tapping the drawer's account row shows the tooltip with "로그아웃" (red) and "탈퇴하기" (gray, smaller) as the only two options, positioned above the account row with a pointer connecting it visually.
- [ ] Tapping "로그아웃" in the tooltip shows the logout alert with the same message text as today's `HomeView` confirmation dialog; confirming triggers the same `onResetToOnboarding` path as before.
- [ ] Tapping "탈퇴하기" in the tooltip shows the delete-account alert with the stronger warning copy; confirming calls a new (possibly stubbed) delete-account callback.
- [ ] Both alerts have a working "취소" that dismisses without side effects.
- [ ] `HomeView`'s old `switchAccountButton`/`isResetConfirmationPresented`/its `.confirmationDialog` are removed — no dead code left behind.
- [ ] `FolderContentsView` and `DetailView` can trigger the same account flow from the drawer (since the drawer, not each screen individually, owns the account row).

## Open Questions / Follow-ups

- If `05-account-deletion` hasn't shipped yet when this brief is implemented, confirm what the "탈퇴하기" confirm button should do in the meantime (e.g. a visible TODO / disabled state) rather than silently doing nothing.
