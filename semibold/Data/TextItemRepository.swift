import CoreData
import Foundation

/// Reads and writes `TextItem` rows — the text-specific detail record for
/// a `DocumentItem` whose `contentType` is `"text"`. Each row is keyed
/// 1:1 off its owning item's id (`itemId`, `STORAGE_ARCHITECTURE.md` §3.3),
/// so lookups are always by that shared id rather than a separate primary
/// key.
///
/// Rendering a document means resolving many items' text detail at once,
/// so callers assembling a whole document (or a page of it) should prefer
/// the batch `find(itemIds:)` over calling `find(itemId:)` once per item
/// — that per-item looping is exactly the N+1 query pattern
/// `STORAGE_ARCHITECTURE.md` §5.2 calls out avoiding.
struct TextItemRepository {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = DatabaseManager.sharedOrFallbackContext) {
        self.context = context
    }

    /// Inserts a new text detail row.
    @discardableResult
    func create(_ item: TextContent) throws -> TextContent {
        let entity = TextItemEntity(context: context)
        apply(item, to: entity)
        try context.save()
        return item
    }

    /// Fetches a single item's text detail by its owning `DocumentItem`'s id.
    func find(itemId: String) throws -> TextContent? {
        try fetchEntity(itemId: itemId).map(TextContent.init(entity:))
    }

    /// Fetches text detail for several items in a single query, keyed by
    /// each row's own `itemId` — the batch counterpart to `find(itemId:)`
    /// (`STORAGE_ARCHITECTURE.md` §5.2's "텍스트 상세 일괄 조회") for callers
    /// resolving a whole document's worth of text items at once.
    func find(itemIds: [String]) throws -> [TextContent] {
        guard !itemIds.isEmpty else { return [] }
        let request = TextItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "itemId IN %@", itemIds)
        return try context.fetch(request).map(TextContent.init(entity:))
    }

    /// Saves changes to an existing text detail row.
    @discardableResult
    func update(_ item: TextContent) throws -> TextContent {
        guard let entity = try fetchEntity(itemId: item.itemId) else {
            throw RepositoryError.recordNotFound
        }
        apply(item, to: entity)
        try context.save()
        return item
    }

    /// Permanently removes a text detail row for direct/standalone use.
    ///
    /// `TextContent` carries no `deletedAt`/timestamps of its own — it's a
    /// pure detail record, not a top-level entity with its own lifecycle
    /// — so unlike `DocumentItemRepository`, there's no soft-delete state
    /// to model here. Everyday content deletion goes through
    /// `DocumentItemRepository.softDelete`/`hardDelete` on the owning
    /// `DocumentItem`, which already removes this row as part of a hard
    /// delete.
    func delete(itemId: String) throws {
        guard let entity = try fetchEntity(itemId: itemId) else { return }
        context.delete(entity)
        try context.save()
    }

    private func fetchEntity(itemId: String) throws -> TextItemEntity? {
        let request = TextItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "itemId == %@", itemId)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func apply(_ item: TextContent, to entity: TextItemEntity) {
        entity.itemId = item.itemId
        entity.textKind = item.textKind
        entity.plainText = item.plainText
        entity.headingLevel = item.headingLevel.map { NSNumber(value: $0) }
        entity.alignment = item.alignment
        entity.isChecked = item.isChecked.map { NSNumber(value: $0) }
        entity.customStyleId = item.customStyleId
    }
}

private extension TextContent {
    init(entity: TextItemEntity) {
        self.init(
            itemId: entity.itemId ?? "",
            textKind: entity.textKind ?? "paragraph",
            plainText: entity.plainText ?? "",
            headingLevel: entity.headingLevel?.intValue,
            alignment: entity.alignment,
            isChecked: entity.isChecked?.boolValue,
            customStyleId: entity.customStyleId
        )
    }
}
