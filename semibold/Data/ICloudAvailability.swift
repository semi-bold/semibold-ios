import Foundation

/// The one piece of `FileManager` that `ICloudAvailability` needs:
/// whether this device is signed into an iCloud account at all.
///
/// `FileManager.default.ubiquityIdentityToken` is a real system API with
/// no test seam of its own — its value depends on the test-runner
/// machine's actual iCloud sign-in state, which unit tests can't control.
/// Wrapping just this property behind a protocol lets tests substitute a
/// fake that reports "signed in" or "signed out" on demand, while
/// `FileManager` itself conforms for free (it already has a matching
/// property) and needs no extra code at call sites.
protocol UbiquityIdentityProviding {
    var ubiquityIdentityToken: (NSCoding & NSCopying & NSObjectProtocol)? { get }
}

extension FileManager: UbiquityIdentityProviding {}

/// Detects whether iCloud is available to this app right now (NO-002
/// §4.2) — i.e. whether the person is signed into iCloud on this device
/// at all. This is the same check the rest of the iCloud sync feature
/// uses to decide whether to even offer iCloud sync, independent of
/// whatever sync mode the person has saved (see `SyncModeStore`).
///
/// A namespace rather than a type someone needs to instantiate — there's
/// no state to hold, just one check.
enum ICloudAvailability {
    /// `true` if this device has an active iCloud account, `false`
    /// otherwise (signed out, or iCloud Drive disabled for this app).
    ///
    /// - Parameter fileManager: The `UbiquityIdentityProviding` to check.
    ///   Defaults to `FileManager.default`; tests inject a fake to
    ///   simulate both "signed in" and "signed out" deterministically,
    ///   regardless of the real machine's iCloud state.
    static func isAvailable(fileManager: UbiquityIdentityProviding = FileManager.default) -> Bool {
        fileManager.ubiquityIdentityToken != nil
    }
}
