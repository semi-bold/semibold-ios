import Foundation

/// The result of asking to switch sync mode from `SettingsView`'s toggle —
/// what `SettingsView` should show in response, before anything has
/// actually changed.
///
/// `SettingsView` always asks this *before* applying the toggle's new
/// position (NO-002 §3.2 "설정 전환 플로우"): re-checking iCloud
/// availability for the 로컬 → iCloud direction, and choosing the matching
/// warning wording, is decision logic worth testing without driving an
/// actual `Toggle`/`Alert`.
enum SyncModeSwitchPrompt: Equatable {
    /// Show the 로컬 → iCloud upload warning (NO-002 §2.4) and, on
    /// confirm, attempt the switch.
    case confirmLocalToICloud
    /// Show the iCloud → 로컬 sync-stop warning (NO-002 §2.4) and, on
    /// confirm, attempt the switch.
    case confirmICloudToLocal
    /// iCloud isn't available right now, so the 로컬 → iCloud attempt is
    /// refused outright (NO-002 §3.2's "불가능 → 안내 메시지: iCloud 설정
    /// 필요") — no switch is attempted, and the toggle should revert.
    case iCloudUnavailable

    /// The confirmation warning's body text, matching NO-002 §2.4's exact
    /// wording for whichever direction this prompt is for. `nil` for
    /// `.iCloudUnavailable`, which shows guidance instead of a
    /// confirm/cancel warning.
    var warningMessage: String? {
        switch self {
        case .confirmLocalToICloud:
            return "기존 로컬 데이터를 iCloud로 업로드합니다."
        case .confirmICloudToLocal:
            return "iCloud 동기화가 중단됩니다. 데이터는 이 기기에 유지됩니다."
        case .iCloudUnavailable:
            return nil
        }
    }
}

/// Decides what should happen when the person flips `SettingsView`'s
/// iCloud-sync toggle, and carries out that decision once confirmed
/// (NO-002 §2.4, §3.2 "설정 전환 플로우").
///
/// Pulled out of the view so the branching — which warning applies, and
/// whether `DatabaseManager.switchMode` actually runs — is testable
/// without driving an actual `Toggle`/`Alert`, mirroring
/// `ICloudConsentChoice`/`RootLaunchState`.
enum SyncModeSwitchAction {
    /// What `SettingsView` should show immediately after the toggle
    /// changes, before anything is switched.
    ///
    /// Mirrors NO-002 §3.2's first branch ("변경 방향?"): going from local
    /// to iCloud re-checks `ICloudAvailability` right now (it may have
    /// changed since the screen last checked it on `onAppear`) and refuses
    /// the attempt if it's not available, instead of trying and failing
    /// the container switch. Going from iCloud back to local never needs
    /// that check — turning sync off doesn't depend on iCloud being
    /// reachable.
    ///
    /// - Parameters:
    ///   - newMode: The mode the toggle's new (not-yet-applied) position
    ///     represents.
    ///   - fileManager: The `UbiquityIdentityProviding` to check iCloud
    ///     availability through. Defaults to `FileManager.default`; tests
    ///     inject a fake to force either state deterministically.
    static func prompt(
        for newMode: SyncMode,
        fileManager: UbiquityIdentityProviding = FileManager.default
    ) -> SyncModeSwitchPrompt {
        switch newMode {
        case .icloud:
            return ICloudAvailability.isAvailable(fileManager: fileManager)
                ? .confirmLocalToICloud
                : .iCloudUnavailable
        case .local:
            return .confirmICloudToLocal
        }
    }

    /// Carries out a confirmed switch: re-initializes storage for
    /// `newMode` via `DatabaseManager.switchMode` and persists the new
    /// preference on success (`switchMode` itself does the persisting —
    /// see its doc comment).
    ///
    /// Doesn't address `switchMode`'s "existing repositories keep reading
    /// the old container" caveat — that's `SettingsView`'s job (rebuilding
    /// whatever already-alive view holds stale repositories) once this
    /// returns `true`.
    ///
    /// - Parameters:
    ///   - newMode: The sync mode to switch to, after the person confirmed
    ///     the warning for this direction.
    ///   - databaseManager: The manager to switch. Defaults to
    ///     `DatabaseManager.shared`; tests pass a throwaway instance so
    ///     this never touches the real on-disk store.
    ///   - storeURL: Where the new container's store should live.
    ///     Defaults to `DatabaseManager.defaultStoreURL()`; tests pass
    ///     `nil` (in-memory) instead.
    ///   - syncModeStore: Where the resulting mode is persisted. Defaults
    ///     to the standard `UserDefaults`-backed store; tests inject one
    ///     backed by an ephemeral suite.
    /// - Returns: `true` if the switch succeeded, `false` if it failed
    ///   (NO-002 §7 "모드 전환 실패") — `databaseManager` is left
    ///   unchanged and `syncModeStore`'s value is untouched in that case,
    ///   so the caller should revert its toggle and surface the failure
    ///   message.
    @MainActor
    static func confirmSwitch(
        to newMode: SyncMode,
        databaseManager: DatabaseManager?,
        storeURL: URL?,
        syncModeStore: SyncModeStore = SyncModeStore()
    ) -> Bool {
        guard let databaseManager else {
            // No container to switch at all (§15.2 "DB 열기 실패" already
            // means the root view shows `DatabaseUnavailableView`, so
            // `SettingsView` is never reachable in this state) — nothing
            // to do.
            return false
        }

        do {
            try databaseManager.switchMode(to: newMode, storeURL: storeURL, syncModeStore: syncModeStore)
            return true
        } catch {
            return false
        }
    }
}
