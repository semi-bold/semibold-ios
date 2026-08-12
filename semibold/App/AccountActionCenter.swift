import Foundation

/// Shared trigger point for the drawer's account flow (`04-account-
/// tooltip-and-alerts`, `Planning_Nav_3_AccountFlow`/FLOW-NAV-003).
///
/// The account row lives in `SidebarDrawerView`
/// (`Views/Components/NavBar/SidebarDrawerView.swift`), which `HomeScreen`,
/// `FolderContentsScreen`, and `DetailView` all mount as a screen-covering
/// overlay — but only `HomeScreen` is constructed with a direct
/// "return to onboarding" closure, and `FolderContentsScreen`/`DetailView`
/// are pushed via `.navigationDestination(for:)` closures registered once
/// at `HomeScreen`'s `NavigationStack` root, so threading that closure
/// through both of their `init`s would be invasive. This mirrors
/// `AppCommandCenter`'s pattern for the exact same "cross-cutting action
/// needs to reach every screen without threading it through every init"
/// problem: a single instance held in `SemiboldApp` as
/// `@State private var accountActionCenter = AccountActionCenter()` (built
/// once via the no-arg initializer, exactly like `commandCenter`), handed
/// down via `.environment(...)` alongside `commandCenter` at the
/// `HomeScreen(...)` call site, and read from `SidebarDrawerView` — the one
/// place the account row lives — via `@Environment(AccountActionCenter.self)`.
/// Environment values propagate to every screen pushed inside that same
/// `NavigationStack`, so `FolderContentsScreen`/`DetailView` pick this up
/// for free.
///
/// Because `resetToOnboarding` needs to capture `SemiboldApp`'s own
/// `launchState`, it can't be supplied at `init` time the way `deleteAccount`
/// is — `SemiboldApp.body` instead assigns it onto the already-built
/// instance's `var` property from an `.onAppear` on the `.home` case's
/// `HomeScreen` (a plain assignment statement can't sit directly inside a
/// `@ViewBuilder`/`@SceneBuilder` case body). That assignment only ever
/// replaces the closure stored on the one shared instance — it never
/// constructs a new `AccountActionCenter`, so identity (and anything
/// `SidebarDrawerView` observes on it) stays stable.
@Observable
final class AccountActionCenter {
    /// Signs the user out (iCloud-mode session) or returns them to Apple
    /// Sign-In (local-mode session) via `OnboardingView` — the same path
    /// `HomeScreen`'s pre-drawer `onResetToOnboarding` already triggered,
    /// now called from the drawer's account tooltip's "로그아웃" alert
    /// instead of a NavBar button. `var`, not `let` — `SemiboldApp` assigns
    /// this onto the shared instance from `body` (see this type's doc
    /// comment above) since it can't be supplied at `init` time.
    var resetToOnboarding: () -> Void

    /// Permanently deletes the account: hard-deletes every folder/document/
    /// content row in the local store, then ends the session and returns to
    /// onboarding (`tasks/NO-008.md` §5.2). Assigned onto the shared
    /// instance from `SemiboldApp`'s `.home` `.onAppear`, mirroring
    /// `resetToOnboarding` — see this type's doc comment above. `var` to
    /// match `resetToOnboarding`, for the same "can't be supplied at
    /// `@State` construction time" reason.
    var deleteAccount: () -> Void

    init(
        resetToOnboarding: @escaping () -> Void = {},
        deleteAccount: @escaping () -> Void = {}
    ) {
        self.resetToOnboarding = resetToOnboarding
        self.deleteAccount = deleteAccount
    }
}
