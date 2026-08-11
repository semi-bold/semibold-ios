import CoreData
import Testing

@testable import semibold

/// Coverage for `NSManagedObjectContext.withTransaction` and the
/// repository `save: false` opt-out it's meant to be used with —
/// `STORAGE_ARCHITECTURE.md` §6's "콘텐츠 생성·수정은 하나의 트랜잭션에서
/// 처리한다" applied to `DocumentItemRepository`/`TextItemRepository`/
/// `TextMarkRepository`.
struct NSManagedObjectContextTransactionTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    @Test("A repository mutation called with save: false isn't persisted until an explicit save")
    func saveFalseLeavesMutationUnsavedUntilExplicitSave() throws {
        let store = try makeStore()
        let repository = TextItemRepository(context: store.context)

        try repository.create(TextContent(itemId: "item-1", textKind: "paragraph", plainText: "Hello"), save: false)

        // A second context on the same persistent store coordinator only
        // ever sees committed data — if this finds the row, the mutation
        // above reached disk despite `save: false`.
        let secondContext = store.container.newBackgroundContext()
        let notYetPersisted = try secondContext.fetch(TextItemEntity.fetchRequest())
        #expect(notYetPersisted.isEmpty)

        try store.context.save()

        let afterSave = try secondContext.fetch(TextItemEntity.fetchRequest())
        #expect(afterSave.count == 1)
    }

    @Test("withTransaction commits several save: false mutations as a single save")
    func withTransactionCommitsAllMutationsTogether() throws {
        let store = try makeStore()
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        try store.context.withTransaction {
            let item = try documentItemRepository.create(
                DocumentItem(documentId: "doc-1", contentType: "text", orderKey: "0100000000"), save: false
            )
            try textItemRepository.create(
                TextContent(itemId: item.id, textKind: "paragraph", plainText: "Hello"), save: false
            )
        }

        let secondContext = store.container.newBackgroundContext()
        #expect(try secondContext.fetch(DocumentItemEntity.fetchRequest()).count == 1)
        #expect(try secondContext.fetch(TextItemEntity.fetchRequest()).count == 1)
    }

    @Test("A failure inside withTransaction propagates without committing any of the prior mutations")
    func withTransactionPropagatesErrorsWithoutCommitting() throws {
        let store = try makeStore()
        let textItemRepository = TextItemRepository(context: store.context)

        #expect(throws: RepositoryError.self) {
            try store.context.withTransaction {
                try textItemRepository.create(
                    TextContent(itemId: "item-1", textKind: "paragraph", plainText: "Hello"), save: false
                )
                // `find(itemId:)`-backed `update` throws `.recordNotFound`
                // for an id that was never created — the closure's second
                // step fails, so the whole transaction's `save()` never
                // runs.
                _ = try textItemRepository.update(
                    TextContent(itemId: "missing", textKind: "paragraph", plainText: "?"), save: false
                )
            }
        }

        let secondContext = store.container.newBackgroundContext()
        #expect(try secondContext.fetch(TextItemEntity.fetchRequest()).isEmpty)
    }
}
