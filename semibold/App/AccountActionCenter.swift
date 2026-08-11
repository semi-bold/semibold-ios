import Foundation

/// Shared trigger point for the drawer's account flow (`04-account-
/// tooltip-and-alerts`, `Planning_Nav_3_AccountFlow`/FLOW-NAV-003).
///
/// The account row lives in `SidebarDrawerView`
/// (`Views/Shared/SidebarDrawerView.swift`), which `HomeView`,
/// `FolderContentsView`, and `DetailView` all mount as a screen-covering
/// overlay — but only `HomeView` is constructed with a direct
/// "return to onboarding" closure, and `FolderContentsView`/`DetailView`
/// are pushed via `.navigationDestination(for:)` closures registered once
/// at `HomeView`'s `NavigationStack` root, so threading that closure
/// through both of their `init`s would be invasive. This mirrors
/// `AppCommandCenter`'s pattern for the exact same "cross-cutting action
/// needs to reach every screen without threading it through every init"
/// problem: a single instance held in `SemiboldApp` as
/// `@State private var accountActionCenter = AccountActionCenter()` (built
/// once via the no-arg initializer, exactly like `commandCenter`), handed
/// down via `.environment(...)` alongside `commandCenter` at the
/// `HomeView(...)` call site, and read from `SidebarDrawerView` — the one
/// place the account row lives — via `@Environment(AccountActionCenter.self)`.
/// Environment values propagate to every screen pushed inside that same
/// `NavigationStack`, so `FolderContentsView`/`DetailView` pick this up
/// for free.
///
/// Because `resetToOnboarding` needs to capture `SemiboldApp`'s own
/// `launchState`, it can't be supplied at `init` time the way `deleteAccount`
/// is — `SemiboldApp.body` instead assigns it onto the already-built
/// instance's `var` property from an `.onAppear` on the `.home` case's
/// `HomeView` (a plain assignment statement can't sit directly inside a
/// `@ViewBuilder`/`@SceneBuilder` case body). That assignment only ever
/// replaces the closure stored on the one shared instance — it never
/// constructs a new `AccountActionCenter`, so identity (and anything
/// `SidebarDrawerView` observes on it) stays stable.
@Observable
final class AccountActionCenter {
    /// Signs the user out (iCloud-mode session) or returns them to Apple
    /// Sign-In (local-mode session) via `OnboardingView` — the same path
    /// `HomeView`'s pre-drawer `onResetToOnboarding` already triggered,
    /// now called from the drawer's account tooltip's "로그아웃" alert
    /// instead of a NavBar button. `var`, not `let` — `SemiboldApp` assigns
    /// this onto the shared instance from `body` (see this type's doc
    /// comment above) since it can't be supplied at `init` time.
    var resetToOnboarding: () -> Void

    /// Deletes the account and its data (local + iCloud) and returns to
    /// onboarding. Currently a no-op placeholder: this brief only needs
    /// the drawer's "탈퇴하기" alert to call a real, wired callback rather
    /// than silently doing nothing — what that callback actually *does*
    /// (the hard-delete itself) is `05-account-deletion`'s job, which will
    /// wire this to the real hard-delete (local Core Data + iCloud,
    /// `tasks/NO-008.md` §5.2) + reset-to-onboarding flow once that brief
    /// lands. `var` to mirror `resetToOnboarding`, even though today it's
    /// still only ever set via `init`'s default.
    var deleteAccount: () -> Void

    init(
        resetToOnboarding: @escaping () -> Void = {},
        deleteAccount: @escaping () -> Void = {}
    ) {
        self.resetToOnboarding = resetToOnboarding
        self.deleteAccount = deleteAccount
    }
}
