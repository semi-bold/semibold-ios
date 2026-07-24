import CoreData
import Foundation

/// Reads and writes `TextMark` rows — the inline formatting spans (bold,
/// italic, links, …) applied to a `TextContent`'s `plainText`
/// (`STORAGE_ARCHITECTURE.md` §3.4). A single text item can carry several
/// marks, so every read here is a batch fetch scoped to one or more
/// items rather than a single-row lookup by mark id.
struct TextMarkRepository {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = DatabaseManager.sharedOrFallbackContext) {
        self.context = context
    }

    /// Inserts a new formatting mark.
    @discardableResult
    func create(_ mark: TextMark) throws -> TextMark {
        let entity = TextMarkEntity(context: context)
        apply(mark, to: entity)
        try context.save()
        return mark
    }

    /// Fetches every mark on a single item, ordered by `startOffset`
    /// ascending so callers can walk them left-to-right over `plainText`
    /// (`STORAGE_ARCHITECTURE.md` §5.3 "서식 일괄 조회").
    func marks(itemId: String) throws -> [TextMark] {
        let request = TextMarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "itemId == %@", itemId)
        request.sortDescriptors = [
            NSSortDescriptor(key: "startOffset", ascending: true),
            NSSortDescriptor(key: "endOffset", ascending: true)
        ]
        return try context.fetch(request).map(TextMark.init(entity:))
    }

    /// Fetches marks for several items in a single query and groups them
    /// by `itemId`, each group ordered by `startOffset` ascending — the
    /// batch counterpart to `marks(itemId:)` for rendering a whole
    /// document's worth of items at once without one formatting query per
    /// item (`STORAGE_ARCHITECTURE.md` §5.3/§5.5).
    func marks(itemIds: [String]) throws -> [String: [TextMark]] {
        guard !itemIds.isEmpty else { return [:] }
        let request = TextMarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "itemId IN %@", itemIds)
        request.sortDescriptors = [
            NSSortDescriptor(key: "itemId", ascending: true),
            NSSortDescriptor(key: "startOffset", ascending: true),
            NSSortDescriptor(key: "endOffset", ascending: true)
        ]
        let marks = try context.fetch(request).map(TextMark.init(entity:))
        return Dictionary(grouping: marks, by: \.itemId)
    }

    /// Permanently removes a single mark (e.g. the user un-bolds a span).
    func delete(id: String) throws {
        let request = TextMarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        guard let entity = try context.fetch(request).first else { return }
        context.delete(entity)
        try context.save()
    }

    /// Permanently removes every mark on one item — used when that item's
    /// `plainText` is edited by an editor that doesn't (yet) adjust mark
    /// offsets to match the new text, so a stale mark can never be applied
    /// to the wrong substring (`DetailViewModel.updateBlockText`'s doc
    /// comment). No-op if the item has no marks.
    func deleteAll(itemId: String) throws {
        let request = TextMarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "itemId == %@", itemId)
        let entities = try context.fetch(request)
        guard !entities.isEmpty else { return }
        for entity in entities {
            context.delete(entity)
        }
        try context.save()
    }

    private func apply(_ mark: TextMark, to entity: TextMarkEntity) {
        entity.id = mark.id
        entity.itemId = mark.itemId
        entity.startOffset = Int64(mark.startOffset)
        entity.endOffset = Int64(mark.endOffset)
        entity.markType = mark.markType
        entity.valueMode = mark.valueMode
        entity.valueText = mark.valueText
    }
}

private extension TextMark {
    init(entity: TextMarkEntity) {
        self.init(
            id: entity.id ?? "",
            itemId: entity.itemId ?? "",
            startOffset: Int(entity.startOffset),
            endOffset: Int(entity.endOffset),
            markType: entity.markType ?? "",
            valueMode: entity.valueMode,
            valueText: entity.valueText
        )
    }
}
