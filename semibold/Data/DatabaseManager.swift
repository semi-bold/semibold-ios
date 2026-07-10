import CoreData
import Foundation

/// Owns the app's single Core Data persistent container and keeps its
/// store loaded.
///
/// semi:bold stores everything locally — folders, documents, and the
/// blocks that make up a document's content — in one on-device database.
/// `DatabaseManager` is the one place that knows where that database file
/// lives and how to load it, so the rest of the app can read/write
/// through Core Data without worrying about setup.
///
/// `makeContainer(syncEnabled:storeURL:)` can build either a local-only
/// (`NSPersistentContainer`) or iCloud-backed
/// (`NSPersistentCloudKitContainer`) container. At launch, `shared` reads
/// the Keychain session's `SessionMode` once to decide which container to
/// build — if the person chose iCloud at onboarding, sync is on from the
/// first database access and never switches at runtime (NO-004 §4.2).
final class DatabaseManager {
    private static var _sharedInstance: DatabaseManager?
    private static var _sharedInitialized = false

    /// Shared instance used across the app, or `nil` if loading the
    /// on-disk persistent store failed (§15.2 "DB 열기 실패").
    ///
    /// Computed on first access and cached. The cache is invalidated by
    /// `resetShared()` — which `SemiboldApp` calls whenever the Keychain
    /// session changes (local ↔ iCloud mode switch) so the next access
    /// opens the correct store for the new session.
    static var shared: DatabaseManager? {
        if _sharedInitialized { return _sharedInstance }
        let session = KeychainSessionStore().load()
        let syncEnabled = session?.mode == .icloud
        let storeURL = syncEnabled
            ? DatabaseManager.cloudStoreURL()
            : DatabaseManager.localStoreURL()
        do {
            _sharedInstance = try DatabaseManager(storeURL: storeURL, syncEnabled: syncEnabled)
            openError = nil
        } catch {
            openError = error
            _sharedInstance = nil
        }
        _sharedInitialized = true
        return _sharedInstance
    }

    /// Invalidates the cached `shared` instance so it is recomputed from
    /// the current Keychain session on the next access. Call this after
    /// saving or deleting a Keychain session (mode switch) and before
    /// transitioning the UI to `HomeView`, so the new home screen opens
    /// the correct store.
    static func resetShared() {
        _sharedInitialized = false
        _sharedInstance = nil
        openError = nil
    }

    /// The error from loading the on-disk persistent store, if `shared`
    /// is `nil`. `nil` while the store loaded successfully (the normal
    /// case).
    private(set) static var openError: Error?

    /// The underlying Core Data container. All repositories read/write
    /// through its view context (or background contexts derived from it).
    ///
    /// Set once at init time and never swapped at runtime — sync mode is
    /// determined at process start from the Keychain session and fixed for
    /// the life of the process (NO-004 §4.2).
    private(set) var persistentContainer: NSPersistentContainer

    /// The app's compiled Core Data model, loaded once and reused by
    /// every `NSPersistentContainer` in this process (the on-disk store
    /// `shared` opens, any in-memory store a `DatabaseManager(storeURL:
    /// nil)` fallback creates, and the in-memory stores
    /// `CoreDataTestStore` creates per test).
    ///
    /// `NSPersistentContainer(name:)`'s default name-only lookup, and
    /// even an explicit `NSManagedObjectModel(contentsOf:)` call repeated
    /// per container, each produce a *new* `NSManagedObjectModel`
    /// instance. Core Data then sees multiple model objects all claiming
    /// the same `codeGenerationType="class"`-generated entity classes
    /// (`FolderEntity`/`DocumentEntity`/`DocumentBlockEntity`), which is
    /// what produces the "Failed to find a unique match for an
    /// NSEntityDescription to a managed object subclass" warning.
    /// Memoizing a single model instance here and handing it to every
    /// container — across both the app target and `semiboldTests`, which
    /// links against `semibold` — keeps that mapping unambiguous.
    static let model: NSManagedObjectModel = {
        guard let modelURL = Bundle(for: DatabaseManager.self).url(
            forResource: "SemiboldModel",
            withExtension: "momd"
        ), let model = NSManagedObjectModel(contentsOf: modelURL) else {
            // A missing/uncompilable model is a broken build product, not
            // a normal runtime failure — there's no reasonable fallback.
            fatalError("Couldn't load SemiboldModel.momd from \(Bundle(for: DatabaseManager.self))")
        }
        return model
    }()

    /// Creates the manager, loading (or creating) the persistent store at
    /// `storeURL` and bringing it online.
    ///
    /// - Parameters:
    ///   - storeURL: Location of the SQLite store file. Defaults to
    ///     `semibold.sqlite` inside the app's Application Support
    ///     directory. Pass `nil` to use an in-memory store (for tests and
    ///     previews).
    ///   - syncEnabled: Whether to build an iCloud-backed
    ///     (`NSPersistentCloudKitContainer`) container instead of a
    ///     local-only one, via `makeContainer(syncEnabled:storeURL:)`.
    ///     `shared` derives this from the Keychain session's `SessionMode`
    ///     at process start (NO-004 §4.2); tests pass it directly.
    /// - Throws: if the persistent store can't be loaded (§15.2 "DB 열기
    ///   실패").
    init(storeURL: URL?, syncEnabled: Bool = false) throws {
        let container = Self.makeContainer(syncEnabled: syncEnabled, storeURL: storeURL)

        // `loadPersistentStores` is callback-based, but for a local SQLite
        // (or in-memory) store it completes synchronously before
        // returning, so capturing the result in `loadError` and checking
        // it right after is safe — this preserves the previous
        // `init(path:) throws` call shape the rest of the app relies on.
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        persistentContainer = container
    }

    /// The managed object context repositories should default to:
    /// `shared`'s view context when the on-disk store loaded
    /// successfully, or a throwaway in-memory context otherwise.
    ///
    /// This only matters for repositories' default-argument expressions
    /// (`DocumentRepository()`, etc.) — when `shared` is `nil`, the root
    /// view shows `DatabaseUnavailableView` instead of any screen that
    /// would construct a repository, so this fallback context is never
    /// actually read from or written to in that case. It exists purely so
    /// those default arguments stay non-optional/non-throwing.
    ///
    /// Repositories resolve this once at construction time. Because
    /// `SemiboldApp` calls `resetShared()` before any mode-switch
    /// transition re-shows `HomeView`, newly constructed repositories
    /// always see the correct container for the active session.
    static var sharedOrFallbackContext: NSManagedObjectContext {
        if let shared {
            return shared.persistentContainer.viewContext
        }
        // swiftlint:disable:next force_try
        return try! DatabaseManager(storeURL: nil).persistentContainer.viewContext
    }

    /// The CloudKit container identifier semi:bold's iCloud-backed store
    /// syncs through. Must match the container registered for this app in
    /// the Apple Developer Console.
    ///
    /// As of this writing, `project.yml`'s `DEVELOPMENT_TEAM` is still
    static let cloudKitContainerIdentifier = "iCloud.com.semibold.semibold"

    /// Builds the persistent container semi:bold should use, branching on
    /// whether the person using the app has turned on iCloud sync.
    ///
    /// Both branches share `DatabaseManager.model` (the one memoized
    /// `NSManagedObjectModel` instance for this process — see its doc
    /// comment) and the store-loading pattern `init(storeURL:)` already
    /// uses, so callers can swap between them without duplicating setup.
    ///
    /// This only constructs the container — it does not load its
    /// persistent store. Callers load the store the same way
    /// `init(storeURL:)` does.
    ///
    ///
    /// - Parameters:
    ///   - syncEnabled: `true` to build an iCloud-backed
    ///     (`NSPersistentCloudKitContainer`) container, `false` for a
    ///     local-only (`NSPersistentContainer`) one.
    ///   - storeURL: Location of the SQLite store file, or `nil` for an
    ///     in-memory store (tests/previews).
    static func makeContainer(syncEnabled: Bool, storeURL: URL?) -> NSPersistentContainer {
        let container: NSPersistentContainer
        if syncEnabled {
            container = NSPersistentCloudKitContainer(name: "SemiboldModel", managedObjectModel: Self.model)
        } else {
            container = NSPersistentContainer(name: "SemiboldModel", managedObjectModel: Self.model)
        }

        if let description = container.persistentStoreDescriptions.first {
            if let storeURL {
                description.url = storeURL
            } else {
                // In-memory store for tests/previews: never touches disk.
                description.url = URL(fileURLWithPath: "/dev/null")
            }

            if syncEnabled {
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: Self.cloudKitContainerIdentifier
                )
            }
        }

        return container
    }

    /// On-disk location for the local-only store (`local.sqlite`).
    /// Completely independent from `cloudStoreURL()` — switching modes
    /// never migrates or merges data between the two files.
    static func localStoreURL() -> URL {
        appSupportURL().appendingPathComponent("local.sqlite")
    }

    /// On-disk location for the iCloud-mirrored store (`cloud.sqlite`).
    /// `NSPersistentCloudKitContainer` uses this as its local mirror of
    /// the CloudKit private database — each device that picks iCloud mode
    /// gets its own copy, which syncs with the shared cloud records.
    static func cloudStoreURL() -> URL {
        appSupportURL().appendingPathComponent("cloud.sqlite")
    }

    private static func appSupportURL() -> URL {
        let fileManager = FileManager.default
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
}
