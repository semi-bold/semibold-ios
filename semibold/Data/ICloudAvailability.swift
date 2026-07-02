import CloudKit
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

/// The subset of `CKContainer` that `ICloudAvailability.unavailableReason`
/// needs — just the async `accountStatus()` method.
///
/// `CKContainer` itself can't be substituted in unit tests without hitting
/// real CloudKit infrastructure. Wrapping the one call behind this protocol
/// lets tests inject a `FakeCKAccountStatusProvider` instead (NO-004 §3.2).
protocol CKAccountStatusProviding {
    func accountStatus() async throws -> CKAccountStatus
}

extension CKContainer: CKAccountStatusProviding {}

/// The reason iCloud is not available to this app right now (NO-004 §3.2,
/// §5.2). Populated by `ICloudAvailability.unavailableReason()` when
/// `isAvailable()` returns `false`.
enum ICloudUnavailableReason: Equatable {
    /// No iCloud account is signed in on this device.
    case noAccount
    /// An iCloud account is signed in, but this app's iCloud access has
    /// been turned off in Settings → Apple ID → iCloud.
    case appAccessDisabled
    /// iCloud is blocked by a device management policy (Screen Time, MDM, etc.).
    case restricted
    /// The account status couldn't be determined — likely a transient
    /// network or server issue.
    case couldNotDetermine
    /// iCloud is temporarily unavailable; the person should try again shortly.
    case temporarilyUnavailable
}

/// Detects whether iCloud is available to this app right now (NO-002
/// §4.2) — i.e. whether the person is signed into iCloud on this device
/// at all. This is the same check the rest of the iCloud sync feature
/// uses to decide whether to even offer iCloud sync, independent of
/// whatever sync mode the person has saved (see `KeychainSessionStore`).
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

    /// Returns the reason iCloud is not available to this app, or `nil`
    /// if iCloud is available (NO-004 §3.2).
    ///
    /// The two-step check matches the spec:
    /// 1. `ubiquityIdentityToken` — fast, synchronous first pass. If it is
    ///    non-nil, iCloud is available and this method returns `nil`.
    /// 2. `CKContainer.accountStatus()` — async, determines *why* the token
    ///    is absent so the UI can show the right per-reason message.
    ///
    /// - Parameters:
    ///   - fileManager: The `UbiquityIdentityProviding` for the fast first
    ///     check. Defaults to `FileManager.default`.
    ///   - container: The `CKAccountStatusProviding` for the async follow-up.
    ///     Defaults to the app's CloudKit container. Tests inject a fake.
    /// - Returns: `nil` when iCloud is available; an `ICloudUnavailableReason`
    ///   otherwise.
    static func unavailableReason(
        fileManager: UbiquityIdentityProviding = FileManager.default,
        container: CKAccountStatusProviding = CKContainer(
            identifier: DatabaseManager.cloudKitContainerIdentifier
        )
    ) async -> ICloudUnavailableReason? {
        // Fast path: token is present, so iCloud is available.
        guard !isAvailable(fileManager: fileManager) else { return nil }

        // Slow path: query CloudKit to learn why the token is absent.
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            return .couldNotDetermine
        }

        switch status {
        case .available:
            // Token was nil but CK says the account is available — the app's
            // iCloud access must be disabled in Settings.
            return .appAccessDisabled
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        case .couldNotDetermine:
            return .couldNotDetermine
        @unknown default:
            return .couldNotDetermine
        }
    }
}
