import Testing

@testable import semibold

/// Smoke coverage for `TextItemRepository`/`TextMarkRepository`/
/// `MediaItemRepository`/`AssetRepository` against a throwaway in-memory
/// database. A full rewrite of the repository test suite happens in a
/// later brief (`tasks/NO-005.md` phase 6); this only proves the
/// repositories written in this brief work, with particular attention to
/// the batch-fetch methods actually issuing a single `IN`-clause query
/// rather than looping the single-item fetch (the whole point of
/// avoiding N+1 queries per `STORAGE_ARCHITECTURE.md` §5).
struct ContentRepositoriesTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    // MARK: - TextItemRepository

    @Test("A created text item is persisted and can be found by itemId")
    func textItemCreateAndFind() throws {
        let store = try makeStore()
        let repository = TextItemRepository(context: store.context)

        let text = TextContent(itemId: "item-1", textKind: "paragraph", plainText: "Hello")
        try repository.create(text)

        let found = try repository.find(itemId: "item-1")
        #expect(found?.plainText == "Hello")
        #expect(found?.textKind == "paragraph")
    }

    @Test("find(itemIds:) batch-fetches text detail for several items in one query")
    func textItemBatchFind() throws {
        let store = try makeStore()
        let repository = TextItemRepository(context: store.context)

        try repository.create(TextContent(itemId: "item-1", textKind: "paragraph", plainText: "One"))
        try repository.create(TextContent(itemId: "item-2", textKind: "heading", plainText: "Two", headingLevel: 2))
        try repository.create(TextContent(itemId: "item-3", textKind: "paragraph", plainText: "Three"))

        let found = try repository.find(itemIds: ["item-1", "item-3"])
        #expect(found.count == 2)
        #expect(Set(found.map(\.itemId)) == ["item-1", "item-3"])
        #expect(found.map(\.plainText).sorted() == ["One", "Three"])

        // An empty batch request never touches the store and returns
        // nothing — used by callers assembling an item with no text
        // children rather than a guard-heavy call site.
        #expect(try repository.find(itemIds: []).isEmpty)
    }

    @Test("update persists field changes and delete removes the row")
    func textItemUpdateAndDelete() throws {
        let store = try makeStore()
        let repository = TextItemRepository(context: store.context)

        var text = try repository.create(TextContent(itemId: "item-1", textKind: "paragraph", plainText: "Hello"))
        text.plainText = "Hello, world"
        text.isChecked = true
        let updated = try repository.update(text)
        #expect(updated.plainText == "Hello, world")

        let found = try repository.find(itemId: "item-1")
        #expect(found?.plainText == "Hello, world")
        #expect(found?.isChecked == true)

        try repository.delete(itemId: "item-1")
        #expect(try repository.find(itemId: "item-1") == nil)
    }

    // MARK: - TextMarkRepository

    @Test("marks(itemId:) returns an item's marks sorted by startOffset")
    func textMarkSingleItemSortedByStartOffset() throws {
        let store = try makeStore()
        let repository = TextMarkRepository(context: store.context)

        try repository.create(TextMark(id: "mark-b", itemId: "item-1", startOffset: 15, endOffset: 22, markType: "inline_code"))
        try repository.create(TextMark(id: "mark-a", itemId: "item-1", startOffset: 3, endOffset: 8, markType: "bold"))

        let marks = try repository.marks(itemId: "item-1")
        #expect(marks.map(\.id) == ["mark-a", "mark-b"])
        #expect(marks.map(\.startOffset) == [3, 15])
    }

    @Test("marks(itemIds:) batch-fetches marks for several items, grouped by itemId")
    func textMarkBatchGroupedByItem() throws {
        let store = try makeStore()
        let repository = TextMarkRepository(context: store.context)

        try repository.create(TextMark(id: "mark-1", itemId: "item-1", startOffset: 3, endOffset: 8, markType: "bold"))
        try repository.create(TextMark(id: "mark-2", itemId: "item-1", startOffset: 15, endOffset: 22, markType: "inline_code"))
        try repository.create(TextMark(id: "mark-3", itemId: "item-2", startOffset: 0, endOffset: 4, markType: "italic"))
        // Belongs to an item not in the requested batch — must not leak in.
        try repository.create(TextMark(id: "mark-4", itemId: "item-3", startOffset: 0, endOffset: 1, markType: "bold"))

        let grouped = try repository.marks(itemIds: ["item-1", "item-2"])
        #expect(Set(grouped.keys) == ["item-1", "item-2"])
        #expect(grouped["item-1"]?.map(\.id) == ["mark-1", "mark-2"])
        #expect(grouped["item-2"]?.map(\.id) == ["mark-3"])
        #expect(grouped["item-3"] == nil)
    }

    @Test("delete removes a single mark")
    func textMarkDelete() throws {
        let store = try makeStore()
        let repository = TextMarkRepository(context: store.context)

        try repository.create(TextMark(id: "mark-1", itemId: "item-1", startOffset: 0, endOffset: 4, markType: "bold"))
        try repository.delete(id: "mark-1")

        #expect(try repository.marks(itemId: "item-1").isEmpty)
    }

    // MARK: - AssetRepository

    @Test("A created asset is persisted and can be found by id")
    func assetCreateAndFind() throws {
        let store = try makeStore()
        let repository = AssetRepository(context: store.context)

        let asset = Asset(id: "asset-1", localPath: "media/asset-1.jpg", mimeType: "image/jpeg", fileName: "asset-1.jpg")
        try repository.create(asset)

        let found = try repository.find(id: "asset-1")
        #expect(found?.mimeType == "image/jpeg")
    }

    @Test("find(ids:) batch-fetches several assets in one query")
    func assetBatchFind() throws {
        let store = try makeStore()
        let repository = AssetRepository(context: store.context)

        try repository.create(Asset(id: "asset-1", localPath: "a.jpg", mimeType: "image/jpeg", fileName: "a.jpg"))
        try repository.create(Asset(id: "asset-2", localPath: "b.jpg", mimeType: "image/jpeg", fileName: "b.jpg"))
        try repository.create(Asset(id: "asset-3", localPath: "c.jpg", mimeType: "image/jpeg", fileName: "c.jpg"))

        let found = try repository.find(ids: ["asset-1", "asset-3"])
        #expect(Set(found.map(\.id)) == ["asset-1", "asset-3"])
    }

    @Test("softDelete marks deletedAt without removing the row, delete removes it")
    func assetSoftDeleteAndHardDelete() throws {
        let store = try makeStore()
        let repository = AssetRepository(context: store.context)

        try repository.create(Asset(id: "asset-1", localPath: "a.jpg", mimeType: "image/jpeg", fileName: "a.jpg"))
        try repository.softDelete(id: "asset-1")

        let softDeleted = try repository.find(id: "asset-1")
        #expect(softDeleted?.deletedAt != nil)

        try repository.delete(id: "asset-1")
        #expect(try repository.find(id: "asset-1") == nil)
    }

    // MARK: - MediaItemRepository

    @Test("A created media item is persisted and can be found by itemId")
    func mediaItemCreateAndFind() throws {
        let store = try makeStore()
        let repository = MediaItemRepository(context: store.context)

        let media = MediaContent(itemId: "item-1", assetId: "asset-1", mediaType: "image")
        try repository.create(media)

        let found = try repository.find(itemId: "item-1")
        #expect(found?.assetId == "asset-1")
    }

    @Test("resolved(itemId:) joins a media item with its referenced asset")
    func mediaItemResolvedSingleJoin() throws {
        let store = try makeStore()
        let assetRepository = AssetRepository(context: store.context)
        let mediaRepository = MediaItemRepository(context: store.context)

        try assetRepository.create(Asset(id: "asset-1", localPath: "a.jpg", mimeType: "image/jpeg", fileName: "a.jpg"))
        try mediaRepository.create(MediaContent(itemId: "item-1", assetId: "asset-1", mediaType: "image"))

        let resolved = try mediaRepository.resolved(itemId: "item-1")
        #expect(resolved?.media.itemId == "item-1")
        #expect(resolved?.asset?.localPath == "a.jpg")
    }

    @Test("resolved(itemIds:) batch-joins several media items with their assets in one pass")
    func mediaItemResolvedBatchJoin() throws {
        let store = try makeStore()
        let assetRepository = AssetRepository(context: store.context)
        let mediaRepository = MediaItemRepository(context: store.context)

        try assetRepository.create(Asset(id: "asset-1", localPath: "a.jpg", mimeType: "image/jpeg", fileName: "a.jpg"))
        try assetRepository.create(Asset(id: "asset-2", localPath: "b.jpg", mimeType: "image/jpeg", fileName: "b.jpg"))
        try mediaRepository.create(MediaContent(itemId: "item-1", assetId: "asset-1", mediaType: "image"))
        try mediaRepository.create(MediaContent(itemId: "item-2", assetId: "asset-2", mediaType: "image"))
        // Two media items sharing the same asset — the batch asset fetch
        // must de-duplicate `assetId`s rather than fetching it twice.
        try mediaRepository.create(MediaContent(itemId: "item-3", assetId: "asset-1", mediaType: "image"))

        let resolved = try mediaRepository.resolved(itemIds: ["item-1", "item-2", "item-3"])
        #expect(resolved.count == 3)
        let byItemId = Dictionary(uniqueKeysWithValues: resolved.map { ($0.media.itemId, $0) })
        #expect(byItemId["item-1"]?.asset?.localPath == "a.jpg")
        #expect(byItemId["item-2"]?.asset?.localPath == "b.jpg")
        #expect(byItemId["item-3"]?.asset?.localPath == "a.jpg")
    }

    @Test("update persists media field changes")
    func mediaItemUpdate() throws {
        let store = try makeStore()
        let repository = MediaItemRepository(context: store.context)

        var media = try repository.create(MediaContent(itemId: "item-1", assetId: "asset-1", mediaType: "image"))
        media.altText = "A description"
        let updated = try repository.update(media)
        #expect(updated.altText == "A description")

        let found = try repository.find(itemId: "item-1")
        #expect(found?.altText == "A description")
    }
}
