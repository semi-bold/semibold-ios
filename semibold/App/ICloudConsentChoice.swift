import Foundation

/// Applies the person's answer to `ICloudConsentView` — "동기화 사용" or
/// "나중에" — to storage (NO-002 §3.1 callouts ③④): persist the chosen
/// `sync_mode` and switch `DatabaseManager` to the matching container.
///
/// Pulled out of `SemiboldApp` as a plain function so the persistence
/// outcome of each button is testable without driving an actual SwiftUI
/// button tap — mirrors how `RootLaunchState.resolve` was separated from
/// the view for the same reason.
enum ICloudConsentChoice {
    /// Records "동기화 사용" or "나중에" and switches storage to match.
    ///
    /// Both directions call `DatabaseManager.switchMode`, which is
    /// itself responsible for persisting `syncModeStore`'s value *only on
    /// success* and rolling back (leaving the current container and the
    /// previously-stored mode untouched) on failure — see that method's
    /// doc comment.
    ///
    /// At onboarding time there's no settings screen to show a "동기화
    /// 설정을 변경하지 못했습니다" alert (that's NO-002 §7's job, deferred
    /// to the settings screen brief), and there's no reasonable "retry"
    /// affordance on a first-launch popup — leaving the person stuck on
    /// the consent screen because real CloudKit connectivity isn't wired
    /// up yet would be worse than just proceeding. So a failed "동기화
    /// 사용" attempt here falls back to local-only silently: `switchMode`
    /// already rolled back to whatever container was active (the
    /// freshly-opened local store from `DatabaseManager.shared`, since
    /// nothing else has run yet at onboarding), so explicitly persisting
    /// `.local` here keeps `sync_mode` truthful about what's actually
    /// running, instead of leaving it unset (which would re-show this
    /// same popup, and likely fail the same way, on every future launch).
    ///
    /// "나중에" always switches to `.local`, which is expected to succeed
    /// (a local-only container needs no entitlements/CloudKit setup) —
    /// but if it somehow doesn't, the same fallback applies: persist
    /// `.local` so the saved preference matches the container that's
    /// actually live.
    ///
    /// `DatabaseManager.switchMode`'s "existing repositories keep reading
    /// the old container" caveat doesn't apply here: this runs *before*
    /// `HomeView` is ever shown, so no repository has been constructed
    /// yet to resolve `DatabaseManager.sharedOrFallbackContext` and go
    /// stale — the first repository any view constructs after this
    /// function returns will read `DatabaseManager.shared`'s
    /// `persistentContainer` fresh, which already reflects the switch.
    ///
    /// - Parameters:
    ///   - sync: `true` for "동기화 사용", `false` for "나중에".
    ///   - databaseManager: The manager to switch. Defaults to
    ///     `DatabaseManager.shared`; tests pass a throwaway instance so
    ///     this never touches the real on-disk store.
    ///   - storeURL: Where the new container's store should live.
    ///     Defaults to `DatabaseManager.defaultStoreURL()`; tests pass
    ///     `nil` (in-memory) instead.
    ///   - syncModeStore: Where the resulting mode is persisted. Defaults
    ///     to the standard `UserDefaults`-backed store; tests inject one
    ///     backed by an ephemeral suite.
    @MainActor
    static func apply(
        sync: Bool,
        databaseManager: DatabaseManager?,
        storeURL: URL?,
        syncModeStore: SyncModeStore = SyncModeStore()
    ) {
        let requestedMode: SyncMode = sync ? .icloud : .local

        guard let databaseManager else {
            // No container to switch at all (§15.2 "DB 열기 실패" already
            // means the root view shows `DatabaseUnavailableView` instead
            // of this popup) — nothing to do.
            return
        }

        do {
            try databaseManager.switchMode(to: requestedMode, storeURL: storeURL, syncModeStore: syncModeStore)
        } catch {
            // Rolled back to the container already active before this
            // call (see doc comment above) — make the saved preference
            // match that reality instead of leaving it as the mode that
            // failed to load.
            syncModeStore.setStoredMode(.local)
        }
    }
}
