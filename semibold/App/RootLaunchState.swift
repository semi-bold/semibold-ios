import Foundation

/// Decides what `SemiboldApp`'s root view should show at launch, before
/// `HomeView`'s `NavigationStack` is ever entered (NO-002 §3.1's "최초
/// 실행 플로우").
///
/// Pulled out of `SemiboldApp` itself so this branching logic — separate
/// from the local-database-failed check that already gates `HomeView` vs
/// `DatabaseUnavailableView` — has a plain value type that's testable
/// without instantiating SwiftUI's `App`/`Scene` types directly.
enum RootLaunchState: Equatable {
    /// The local database couldn't be opened at launch (§15.2 "DB 열기
    /// 실패") — show `DatabaseUnavailableView` instead of anything else.
    case databaseUnavailable
    /// First launch (`sync_mode` has never been saved) and iCloud is
    /// available on this device right now — show `ICloudConsentView`
    /// over `HomeView` so the person can choose a sync mode before using
    /// the app (NO-002 §3.1, "iCloud 동기화 동의 팝업 표시" branch).
    case showICloudConsent
    /// Either this isn't the first launch (a sync mode was already
    /// chosen), or iCloud isn't available on this device — go straight
    /// to `HomeView` with no popup. NO-002 §3.1's "불가능" branch is
    /// folded in here: an unavailable iCloud account always means
    /// "proceed locally, silently", the same as an already-answered
    /// first launch.
    case home

    /// Computes which state the root view should be in right now.
    ///
    /// iCloud availability is deliberately re-checked on every launch
    /// rather than cached: NO-002 §6 treats "iCloud 가용성 = false" as a
    /// per-launch condition (it can flip if the person signs in/out of
    /// iCloud between launches), not a one-time decision baked into
    /// `sync_mode`. Only an explicit "동기화 사용"/"나중에" answer writes
    /// to `SyncModeStore` — simply finding iCloud unavailable does not,
    /// so the consent prompt is correctly offered again on a later
    /// launch once iCloud becomes available, instead of being
    /// permanently skipped after one unlucky launch.
    ///
    /// - Parameters:
    ///   - isDatabaseAvailable: Whether `DatabaseManager.shared` loaded
    ///     successfully. Takes priority over every other check — there's
    ///     nothing to read/write from if storage itself failed.
    ///   - syncModeStore: Where the person's saved sync preference (or
    ///     lack of one) is read from. Defaults to the standard
    ///     `UserDefaults`-backed store; tests inject one backed by an
    ///     ephemeral suite.
    ///   - fileManager: The `UbiquityIdentityProviding` iCloud
    ///     availability is checked through. Defaults to
    ///     `FileManager.default`; tests inject a fake to force either
    ///     state deterministically.
    static func resolve(
        isDatabaseAvailable: Bool,
        syncModeStore: SyncModeStore = SyncModeStore(),
        fileManager: UbiquityIdentityProviding = FileManager.default
    ) -> RootLaunchState {
        guard isDatabaseAvailable else {
            return .databaseUnavailable
        }
        guard syncModeStore.storedMode == nil else {
            return .home
        }
        return ICloudAvailability.isAvailable(fileManager: fileManager) ? .showICloudConsent : .home
    }
}
