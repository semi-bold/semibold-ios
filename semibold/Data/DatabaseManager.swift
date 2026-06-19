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
/// This is the local-only (`NSPersistentContainer`) shape of the
/// container. iCloud sync branching (`NSPersistentCloudKitContainer`) is
/// layered on top of this in a later step — see
/// `.claude/features/02-icloud-sync-branching.md`.
final class DatabaseManager {
    /// Shared instance used across the app, or `nil` if loading the
    /// on-disk persistent store failed at launch (§15.2 "DB 열기 실패").
    ///
    /// Computed once and cached: if this is `nil`, `openError` holds the
    /// underlying error and the root view shows the
    /// "로컬 저장소를 열 수 없습니다." message instead of `HomeView`
    /// (see `SemiboldApp`/`DatabaseUnavailableView`).
    static let shared: DatabaseManager? = {
        do {
            return try DatabaseManager(storeURL: DatabaseManager.defaultStoreURL())
        } catch {
            openError = error
            return nil
        }
    }()

    /// The error from loading the on-disk persistent store, if `shared`
    /// is `nil`. `nil` while the store loaded successfully (the normal
    /// case).
    private(set) static var openError: Error?

    /// The underlying Core Data container. All repositories read/write
    /// through its view context (or background contexts derived from it).
    let persistentContainer: NSPersistentContainer

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
    /// - Parameter storeURL: Location of the SQLite store file. Defaults
    ///   to `semibold.sqlite` inside the app's Application Support
    ///   directory. Pass `nil` to use an in-memory store (for tests and
    ///   previews).
    /// - Throws: if the persistent store can't be loaded (§15.2 "DB 열기
    ///   실패").
    init(storeURL: URL?) throws {
        let container = NSPersistentContainer(name: "SemiboldModel", managedObjectModel: Self.model)

        if let description = container.persistentStoreDescriptions.first {
            if let storeURL {
                description.url = storeURL
            } else {
                // In-memory store for tests/previews: never touches disk.
                description.url = URL(fileURLWithPath: "/dev/null")
            }
        }

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
    static var sharedOrFallbackContext: NSManagedObjectContext {
        if let shared {
            return shared.persistentContainer.viewContext
        }
        // swiftlint:disable:next force_try
        return try! DatabaseManager(storeURL: nil).persistentContainer.viewContext
    }

    /// Default on-disk location for the local store: a `semibold.sqlite`
    /// file inside the app's Application Support directory, creating
    /// that directory if it doesn't exist yet.
    static func defaultStoreURL() -> URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try? fileManager.createDirectory(
                at: appSupportURL,
                withIntermediateDirectories: true
            )
        }

        return appSupportURL.appendingPathComponent("semibold.sqlite")
    }
}
