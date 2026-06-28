import Foundation

/// The two ways semi:bold can store a person's data, as saved to
/// `UserDefaults` (NO-002 §4.3, §6).
///
/// `local` is an explicit choice the person made (or the only option when
/// iCloud isn't available) — it's distinct from never having chosen at
/// all, which `SyncModeStore.storedMode` represents as `nil` rather than
/// as this enum's `.local` case.
enum SyncMode: String {
    /// Data syncs through iCloud (`NSPersistentCloudKitContainer`) and
    /// survives a reinstall.
    case icloud
    /// Data stays in this device's app container
    /// (`NSPersistentContainer`) and is lost if the app is deleted.
    case local
}

/// Reads and writes the person's saved sync preference (NO-002 §4.3, §6).
///
/// This only manages the *preference* — it doesn't decide which
/// `NSPersistentContainer` subclass to build (`DatabaseManager`) or wire
/// that decision into app launch (a later step in this brief). It does,
/// however, fold in `ICloudAvailability` so callers get the mode the app
/// should actually behave as right now, not just the raw saved value: per
/// NO-002 §6's last rule, an unavailable iCloud account forces local-only
/// behavior even if the person previously chose iCloud sync.
///
/// `UserDefaults` is injectable (defaulting to `.standard`), mirroring the
/// injection pattern `DatabaseManager`/`ICloudAvailability` already use in
/// this brief, so tests can use a throwaway suite instead of polluting
/// the app's real defaults.
struct SyncModeStore {
    /// The `UserDefaults` key NO-002 §4.3 specifies.
    static let key = "sync_mode"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// The literal saved preference, or `nil` if the key has never been
    /// written — which NO-002 §4.3/§6 treats as "first launch" (the
    /// person hasn't seen the iCloud consent prompt yet), not as an
    /// implicit choice of `.local`.
    ///
    /// An unrecognized stored string (shouldn't happen outside of manual
    /// tampering, since `setStoredMode` only ever writes the two known
    /// raw values) also reads back as `nil` rather than crashing, so a
    /// corrupted default behaves the same as "first launch".
    var storedMode: SyncMode? {
        guard let rawValue = userDefaults.string(forKey: Self.key) else {
            return nil
        }
        return SyncMode(rawValue: rawValue)
    }

    /// Persists `mode` as the literal raw string NO-002 §4.3 specifies
    /// (`"icloud"`/`"local"`), or clears the key entirely when `mode` is
    /// `nil` — returning to the "first launch" state.
    func setStoredMode(_ mode: SyncMode?) {
        guard let mode else {
            userDefaults.removeObject(forKey: Self.key)
            return
        }
        userDefaults.set(mode.rawValue, forKey: Self.key)
    }

    /// The mode the app should actually behave as right now, accounting
    /// for whether iCloud is even available on this device (NO-002 §6:
    /// "iCloud 가용성 = false → sync_mode 값과 무관하게 로컬 전용으로
    /// 강제 동작").
    ///
    /// - `storedMode == .icloud` and iCloud is available → `.icloud`.
    /// - `storedMode == .icloud` but iCloud is *not* available → `.local`
    ///   (forced fallback, regardless of the saved preference).
    /// - `storedMode == .local` → `.local`, iCloud availability doesn't
    ///   matter.
    /// - `storedMode == nil` (first launch) → `.local`, since there's no
    ///   saved choice to honor yet; callers that need to distinguish
    ///   "first launch, show the consent prompt" from "explicitly chose
    ///   local" should check `storedMode` directly instead of this
    ///   property.
    ///
    /// - Parameter fileManager: The `UbiquityIdentityProviding` to check
    ///   iCloud availability through. Defaults to `FileManager.default`;
    ///   tests inject a fake (see `ICloudAvailabilityTests`) to force
    ///   "unavailable" deterministically.
    func effectiveMode(fileManager: UbiquityIdentityProviding = FileManager.default) -> SyncMode {
        guard storedMode == .icloud else {
            return .local
        }
        return ICloudAvailability.isAvailable(fileManager: fileManager) ? .icloud : .local
    }
}
