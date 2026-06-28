import CoreData

@testable import semibold

/// A fresh, isolated Core Data store for a single test.
///
/// Every repository test in this target previously got a throwaway
/// in-memory GRDB `DatabaseQueue` per test; this is the Core Data
/// equivalent — a brand-new `NSPersistentContainer` loaded against an
/// in-memory store (`NSInMemoryStoreType`, not a file path), so nothing
/// ever touches disk and nothing leaks between tests.
struct CoreDataTestStore {
    let container: NSPersistentContainer

    /// The context repositories under test should read/write through.
    var context: NSManagedObjectContext { container.viewContext }

    /// Loads the app's `SemiboldModel` schema into a brand-new in-memory
    /// store.
    ///
    /// `loadPersistentStores` is callback-based, but for an in-memory
    /// store it completes synchronously before returning, so capturing
    /// the result and checking it right after — the same assumption
    /// `DatabaseManager.init` relies on — is safe here too.
    ///
    /// Uses `DatabaseManager.model` — the single `NSManagedObjectModel`
    /// instance memoized for the whole process — instead of loading its
    /// own copy. `NSPersistentContainer(name:)`'s default name-only
    /// lookup, and even a from-scratch `NSManagedObjectModel(contentsOf:)`
    /// call per container, each produce a *new* model instance; Core Data
    /// then sees multiple model objects all claiming the same
    /// `codeGenerationType="class"`-generated entity classes
    /// (`FolderEntity`/`DocumentEntity`/`DocumentBlockEntity`), which is
    /// what produces the "Failed to find a unique match for an
    /// NSEntityDescription to a managed object subclass" warning.
    /// `semiboldTests` links against `semibold` (and runs hosted inside
    /// its process), so reusing `DatabaseManager.model` here keeps every
    /// container in the process — the app's on-disk store and every
    /// per-test in-memory store — pointing at the same model object.
    init() throws {
        let container = NSPersistentContainer(
            name: "SemiboldModel",
            managedObjectModel: DatabaseManager.model
        )

        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        self.container = container
    }

    /// Simulates a persistence failure (e.g. the on-disk store becoming
    /// unavailable mid-session) by detaching the in-memory store from its
    /// coordinator, so the next `context.save()` throws instead of
    /// succeeding — the Core Data equivalent of closing the underlying
    /// GRDB connection.
    func simulateStoreFailure() throws {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }
}
