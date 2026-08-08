# Feature: 05-account-deletion

## Source

- `tasks/NO-008.md` §1.1 (Apple 심사 가이드라인 5.1.1(v) — 계정 생성을 지원하면 앱 내 삭제도 지원해야 함), §2.1, §5.2 (계정 탈퇴 — iCloud 데이터 삭제, 확인이 필요한 항목)

## Scope

- In scope:
  - Implement the `onDeleteAccount`-style callback wired from `04-account-tooltip-and-alerts`'s delete-account alert: permanently (hard) delete every `Folder`/`Document`/`DocumentItem`/`TextItem`/`TextMark`/`MediaItem`/`Asset` row for the current local store — not a soft delete, since this is a full account wipe, not a recoverable action.
  - Delete the Keychain session (`KeychainSessionStore().delete()`), call `DatabaseManager.resetShared()`, and return the user to onboarding — mirroring the existing credential-revocation path in `SemiboldApp.swift` (`checkAppleCredentialRevocation`) as the closest existing precedent for "wipe session + go to onboarding".
  - For iCloud-mode sessions: at minimum, perform the same local hard-delete (which will eventually export as deletes to CloudKit via `NSPersistentCloudKitContainer`'s normal, non-guaranteed-timing path) — see Open Questions for what's *not* solved by this brief.
- Out of scope / deferred:
  - A synchronous, confirmed-on-the-spot CloudKit deletion (e.g. direct `CKDatabase` record-zone deletion) — per `tasks/NO-008.md` §5.2 this needs further engineering decision alongside NO-006 and is explicitly not resolved by this brief. Implement the reliable part (local deletion) now; do not block this brief on solving CloudKit's guarantee gap.

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `Planning_Nav_3_AccountFlow` (FLOW-NAV-003) | data-layer + app-state wiring, no new UI | Triggered by `04-account-tooltip-and-alerts`'s confirm button |

## Decisions & Deviations

- Hard delete, not soft delete: existing `softDelete` methods leave rows in place with `deletedAt` set (recoverable, and still present for CloudKit to sync) — that's the wrong tool for "the user asked to permanently delete their account." Use the existing `hardDelete` paths (`DocumentItemRepository.hardDelete`, etc.) or add equivalents where a repository is missing a hard-delete method for its root entities.
- Reuse `SemiboldApp`'s credential-revocation reset pattern (`KeychainSessionStore().delete()` → `DatabaseManager.resetShared()` → `launchState = .showOnboarding`) as the shape for "end the session and go to onboarding" — don't invent a second way to do the same thing.

## Acceptance Criteria

- [ ] Confirming "탈퇴하기" permanently deletes every folder, document, and content row in the local store (verifiable via repository queries returning empty afterward, including hard-deleted rows — not just `deletedAt`-filtered ones).
- [ ] The Keychain session is deleted and the app returns to the onboarding screen, matching the credential-revocation flow's behavior.
- [ ] A local-mode (non-iCloud) account deletion works fully synchronously and needs no iCloud-specific handling.
- [ ] An iCloud-mode account deletion performs the same local hard-delete (CloudKit-side propagation timing is explicitly out of scope per Decisions).
- [ ] Unit tests cover: local-mode deletion wipes all data and returns a fresh onboarding state; iCloud-mode deletion does the same for the local store.

## Open Questions / Follow-ups

- **Not resolved by this brief**: whether/how to guarantee CloudKit-side data is actually removed (vs. relying on `NSPersistentCloudKitContainer`'s best-effort export of local deletes). Per `tasks/NO-008.md` §5.2, this needs a decision alongside NO-006 (e.g. direct `CKDatabase` zone deletion) — flag this gap explicitly to the user/App Review context rather than silently treating "local hard-delete done" as "fully compliant with account-deletion requirements."
