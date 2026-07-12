import CloudKit
import Foundation
import Testing

@testable import semibold

/// A `CKAccountStatusProviding` stand-in that always throws, simulating
/// a CloudKit error so `unavailableReason()` falls back to `.couldNotDetermine`.
private struct ThrowingCKAccountStatusProvider: CKAccountStatusProviding {
    func accountStatus() async throws -> CKAccountStatus {
        throw CKError(.networkUnavailable)
    }
}

/// Verifies `ICloudAvailability.isAvailable(fileManager:)` reads the
/// iCloud sign-in state from `ubiquityIdentityToken` (NO-002 §4.2), and
/// `ICloudAvailability.unavailableReason(fileManager:container:)` maps each
/// `CKAccountStatus` value to the correct `ICloudUnavailableReason`
/// (NO-004 §3.2).
///
/// All paths are driven through `FakeUbiquityIdentityProvider` /
/// `FakeCKAccountStatusProvider` rather than the real `FileManager` or
/// `CKContainer`, keeping the results deterministic regardless of whether
/// the machine running these tests is actually signed into iCloud.
struct ICloudAvailabilityTests {

    // MARK: - isAvailable

    @Test("isAvailable is true when the device has an iCloud identity token")
    func availableWhenTokenPresent() {
        #expect(ICloudAvailability.isAvailable(fileManager: FakeUbiquityIdentityProvider.signedIn))
    }

    @Test("isAvailable is false when the device has no iCloud identity token")
    func unavailableWhenTokenMissing() {
        #expect(!ICloudAvailability.isAvailable(fileManager: FakeUbiquityIdentityProvider.signedOut))
    }

    // MARK: - unavailableReason

    @Test("unavailableReason returns nil when token is present (iCloud is available)")
    func unavailableReasonNilWhenAvailable() async {
        // Token is present → isAvailable() returns true → fast path returns nil.
        let reason = await ICloudAvailability.unavailableReason(
            fileManager: FakeUbiquityIdentityProvider.signedIn,
            container: FakeCKAccountStatusProvider(status: .available)
        )
        #expect(reason == nil)
    }

    @Test("unavailableReason returns .noAccount when CKAccountStatus is noAccount")
    func unavailableReasonNoAccount() async {
        let reason = await ICloudAvailability.unavailableReason(
            fileManager: FakeUbiquityIdentityProvider.signedOut,
            container: FakeCKAccountStatusProvider(status: .noAccount)
        )
        #expect(reason == .noAccount)
    }

    @Test("unavailableReason returns .appAccessDisabled when account is available but token is nil")
    func unavailableReasonAppAccessDisabled() async {
        // Token absent + CK reports .available → app's iCloud access is off in Settings.
        let reason = await ICloudAvailability.unavailableReason(
            fileManager: FakeUbiquityIdentityProvider.signedOut,
            container: FakeCKAccountStatusProvider(status: .available)
        )
        #expect(reason == .appAccessDisabled)
    }

    @Test("unavailableReason returns .restricted when CKAccountStatus is restricted")
    func unavailableReasonRestricted() async {
        let reason = await ICloudAvailability.unavailableReason(
            fileManager: FakeUbiquityIdentityProvider.signedOut,
            container: FakeCKAccountStatusProvider(status: .restricted)
        )
        #expect(reason == .restricted)
    }

    @Test("unavailableReason returns .temporarilyUnavailable when CKAccountStatus is temporarilyUnavailable")
    func unavailableReasonTemporarilyUnavailable() async {
        let reason = await ICloudAvailability.unavailableReason(
            fileManager: FakeUbiquityIdentityProvider.signedOut,
            container: FakeCKAccountStatusProvider(status: .temporarilyUnavailable)
        )
        #expect(reason == .temporarilyUnavailable)
    }

    @Test("unavailableReason returns .couldNotDetermine when accountStatus() throws")
    func unavailableReasonCouldNotDetermineOnThrow() async {
        let reason = await ICloudAvailability.unavailableReason(
            fileManager: FakeUbiquityIdentityProvider.signedOut,
            container: ThrowingCKAccountStatusProvider()
        )
        #expect(reason == .couldNotDetermine)
    }
}
