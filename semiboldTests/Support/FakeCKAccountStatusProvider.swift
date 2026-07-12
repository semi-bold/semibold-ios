import CloudKit
import Foundation
@testable import semibold

/// A stand-in for `CKContainer` that returns a pre-configured
/// `CKAccountStatus` without hitting real CloudKit infrastructure.
///
/// Injected into `ICloudAvailability.unavailableReason(container:)` in
/// unit tests so the async CloudKit call is deterministic and offline-safe
/// (NO-004 §3.2).
struct FakeCKAccountStatusProvider: CKAccountStatusProviding {
    /// The status this fake will report when `accountStatus()` is called.
    let status: CKAccountStatus

    func accountStatus() async throws -> CKAccountStatus {
        status
    }
}
