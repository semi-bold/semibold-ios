import CoreData
import Foundation

/// Permanently wipes every folder, document, and content row from the
/// current local store — the data-layer half of "탈퇴하기" (account
/// deletion, `tasks/NO-008.md` §5.2). Kept as its own small entry point
/// (rather than living inline in `SemiboldApp.deleteAccount()`) so the
/// part of account deletion actually worth unit-testing — did every row
/// really disappear, including already soft-deleted ones? — can run
/// against a throwaway `CoreDataTestStore` context instead of the app's
/// real `DatabaseManager.shared` store. `SemiboldApp.deleteAccount()`
/// calls this and then layers the session-level steps on top (Keychain
/// delete, `DatabaseManager.resetShared()`, returning to onboarding).
///
/// `FolderRepository.hardDeleteAll()` and `DocumentRepository.
/// hardDeleteAll()` each hard-delete every *root-level* folder/document
/// (regardless of its own `deletedAt` state, not just live ones) — their
/// existing `hardDelete(id:)` cascades already sweep up every nested
/// folder, document, and content row underneath, so together these two
/// calls clear every `Folder`/`Document`/`DocumentItem`/`TextItem`/
/// `TextMark`/`MediaItem` row in the store. `Asset` rows are the one
/// thing that cascade doesn't reach (a `MediaItem` only references an
/// asset by id, and assets can be shared across items), so
/// `AssetRepository.hardDeleteAll()` clears those separately.
///
/// This only wipes the *local* store the current session's
/// `DatabaseManager` points at (`local.sqlite` or `cloud.sqlite`,
/// whichever the session is using) — an iCloud-mode session's CloudKit-side
/// copy is expected to catch up via `NSPersistentCloudKitContainer`'s
/// normal, best-effort export of local deletes, not deleted synchronously
/// here. Whether/how to guarantee the CloudKit-side copy is actually gone
/// (e.g. a direct `CKDatabase` zone deletion) is a known open question
/// (`tasks/NO-008.md` §5.2) that this wipe does not attempt to solve.
enum AccountDataWipe {
    static func wipeAll(context: NSManagedObjectContext = DatabaseManager.sharedOrFallbackContext) throws {
        try FolderRepository(context: context).hardDeleteAll()
        try DocumentRepository(context: context).hardDeleteAll()
        try AssetRepository(context: context).hardDeleteAll()
    }
}
