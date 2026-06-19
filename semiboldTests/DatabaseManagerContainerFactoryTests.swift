import CoreData
import Testing

@testable import semibold

/// Verifies `DatabaseManager.makeContainer(syncEnabled:storeURL:)` branches
/// to the right container type (NO-002 §4.1).
///
/// These only construct the container and inspect its type/configuration —
/// they never call `loadPersistentStores` on the iCloud-backed
/// (`NSPersistentCloudKitContainer`) variant. Apple Developer Console setup
/// (Team ID, `semibold.entitlements`) hasn't happened yet for this app, so
/// actually loading a CloudKit-backed store would fail; that's expected and
/// tracked in `.claude/features/02-icloud-sync-branching.md`, not something
/// these tests should try to work around.
struct DatabaseManagerContainerFactoryTests {
    @Test("syncEnabled: true builds an NSPersistentCloudKitContainer")
    func syncEnabledBuildsCloudKitContainer() {
        let container = DatabaseManager.makeContainer(syncEnabled: true, storeURL: nil)

        #expect(container is NSPersistentCloudKitContainer)
    }

    @Test("syncEnabled: true sets the semi:bold CloudKit container identifier on the store description")
    func syncEnabledSetsCloudKitContainerIdentifier() {
        let container = DatabaseManager.makeContainer(syncEnabled: true, storeURL: nil)

        let description = container.persistentStoreDescriptions.first
        #expect(description?.cloudKitContainerOptions?.containerIdentifier == DatabaseManager.cloudKitContainerIdentifier)
    }

    @Test("syncEnabled: false builds a plain NSPersistentContainer, not a CloudKit one")
    func syncDisabledBuildsLocalOnlyContainer() {
        let container = DatabaseManager.makeContainer(syncEnabled: false, storeURL: nil)

        #expect(!(container is NSPersistentCloudKitContainer))

        let description = container.persistentStoreDescriptions.first
        #expect(description?.cloudKitContainerOptions == nil)
    }

    @Test("Both branches share DatabaseManager's single memoized managed object model")
    func bothBranchesShareTheSameModelInstance() {
        let cloudContainer = DatabaseManager.makeContainer(syncEnabled: true, storeURL: nil)
        let localContainer = DatabaseManager.makeContainer(syncEnabled: false, storeURL: nil)

        #expect(cloudContainer.managedObjectModel === DatabaseManager.model)
        #expect(localContainer.managedObjectModel === DatabaseManager.model)
    }

    @Test("The local-only container can actually load its (in-memory) store")
    func localOnlyContainerLoadsSuccessfully() throws {
        let container = DatabaseManager.makeContainer(syncEnabled: false, storeURL: nil)

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        #expect(loadError == nil)
    }
}
