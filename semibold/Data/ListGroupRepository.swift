import CoreData
import Foundation

/// Reads and writes `ListGroup` rows (`Models/ListGroup.swift`'s doc
/// comment). No Core Data relationships — `documentId` and the
/// `DocumentItem.listGroupId` back-reference are plain string foreign
/// keys, matching `DocumentItemRepository`'s own style
/// (`STORAGE_ARCHITECTURE.md` §5).
struct ListGroupRepository {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = DatabaseManager.sharedOrFallbackContext) {
        self.context = context
    }

    /// Inserts a new list group. Pass `save: false` to fold this into a
    /// caller's `context.withTransaction { ... }` alongside other
    /// repository mutations instead of committing on its own.
    @discardableResult
    func create(_ group: ListGroup, save: Bool = true) throws -> ListGroup {
        let entity = ListGroupEntity(context: context)
        entity.id = group.id
        entity.documentId = group.documentId
        entity.listType = group.listType
        if save { try context.save() }
        return group
    }

    func find(id: String) throws -> ListGroup? {
        try fetchEntity(id: id).map(ListGroup.init(entity:))
    }

    /// The number of `DocumentItem`s still live (non-soft-deleted) in
    /// `listGroupId` — a group whose count reaches zero has no reason to
    /// keep existing (`DetailViewModel`'s exit/merge/delete paths use
    /// this to clean up an orphaned group).
    func liveMemberCount(listGroupId: String) throws -> Int {
        let request = DocumentItemEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "listGroupId == %@", listGroupId),
            NSPredicate(format: "deletedAt == nil")
        ])
        return try context.count(for: request)
    }

    /// Permanently removes a list group row. Groups carry no content of
    /// their own (`Models/ListGroup.swift`'s doc comment), so there's no
    /// soft-delete/restore path to preserve — this is the only way a
    /// group row goes away.
    func hardDelete(id: String) throws {
        guard let entity = try fetchEntity(id: id) else { return }
        context.delete(entity)
        try context.save()
    }

    private func fetchEntity(id: String) throws -> ListGroupEntity? {
        let request = ListGroupEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}

private extension ListGroup {
    init(entity: ListGroupEntity) {
        self.init(
            id: entity.id ?? "",
            documentId: entity.documentId ?? "",
            listType: entity.listType ?? ""
        )
    }
}
