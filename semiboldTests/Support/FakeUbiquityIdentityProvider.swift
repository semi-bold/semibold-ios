import Foundation
@testable import semibold

/// A stand-in for `FileManager` that reports whatever iCloud sign-in state a
/// test asks for, instead of the real device/simulator's actual account
/// state — keeps `ICloudAvailability`/`SyncModeStore` tests deterministic
/// regardless of whether the machine running them is signed into iCloud.
struct FakeUbiquityIdentityProvider: UbiquityIdentityProviding {
    let ubiquityIdentityToken: (NSCoding & NSCopying & NSObjectProtocol)?

    static let signedIn = FakeUbiquityIdentityProvider(ubiquityIdentityToken: NSString("fake-token"))
    static let signedOut = FakeUbiquityIdentityProvider(ubiquityIdentityToken: nil)
}
