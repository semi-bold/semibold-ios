import Foundation
import Testing

@testable import semibold

/// Verifies `ICloudAvailability.isAvailable(fileManager:)` reads the
/// iCloud sign-in state from `ubiquityIdentityToken` (NO-002 §4.2).
///
/// Both paths are driven through `FakeUbiquityIdentityProvider` rather
/// than the real `FileManager.default`, so the result is deterministic
/// regardless of whether the machine running these tests is actually
/// signed into iCloud.
struct ICloudAvailabilityTests {
    /// A stand-in for `FileManager` that reports whatever sign-in state a
    /// test asks for, instead of the real device/simulator's iCloud
    /// account state.
    struct FakeUbiquityIdentityProvider: UbiquityIdentityProviding {
        let ubiquityIdentityToken: (NSCoding & NSCopying & NSObjectProtocol)?

        static let signedIn = FakeUbiquityIdentityProvider(ubiquityIdentityToken: NSString("fake-token"))
        static let signedOut = FakeUbiquityIdentityProvider(ubiquityIdentityToken: nil)
    }

    @Test("isAvailable is true when the device has an iCloud identity token")
    func availableWhenTokenPresent() {
        #expect(ICloudAvailability.isAvailable(fileManager: FakeUbiquityIdentityProvider.signedIn))
    }

    @Test("isAvailable is false when the device has no iCloud identity token")
    func unavailableWhenTokenMissing() {
        #expect(!ICloudAvailability.isAvailable(fileManager: FakeUbiquityIdentityProvider.signedOut))
    }
}
