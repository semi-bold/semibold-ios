import CoreData
import Foundation

/// Reads and writes `Asset` rows — the locally stored files (images,
/// video, audio, other attachments) that `MediaContent` items reference
/// by `assetId` (`STORAGE_ARCHITECTURE.md` §3.5). An asset can be shared
/// across more than one `MediaContent`, so this repository never assumes
/// a 1:1 relationship with a single document item.
struct AssetRepository {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = DatabaseManager.sharedOrFallbackContext) {
        self.context = context
    }

    /// Registers a new locally stored file.
    @discardableResult
    func create(_ asset: Asset) throws -> Asset {
        let entity = AssetEntity(context: context)
        apply(asset, to: entity)
        try context.save()
        return asset
    }

    /// Fetches a single asset by id, including soft-deleted ones.
    func find(id: String) throws -> Asset? {
        try fetchEntity(id: id).map(Asset.init(entity:))
    }

    /// Fetches several assets in a single query — the batch companion to
    /// `find(id:)`, used by `MediaItemRepository`'s join-style reads so
    /// resolving a whole document's worth of media doesn't issue one
    /// asset query per item (`STORAGE_ARCHITECTURE.md` §5.4).
    func find(ids: [String]) throws -> [Asset] {
        guard !ids.isEmpty else { return [] }
        let request = AssetEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", ids)
        return try context.fetch(request).map(Asset.init(entity:))
    }

    /// Saves changes to an existing asset, refreshing `updatedAt`.
    @discardableResult
    func update(_ asset: Asset) throws -> Asset {
        var updated = asset
        updated.updatedAt = Date()
        guard let entity = try fetchEntity(id: updated.id) else {
            throw RepositoryError.recordNotFound
        }
        apply(updated, to: entity)
        try context.save()
        return updated
    }

    /// Marks an asset as deleted without removing its row or its
    /// underlying file, so it can be restored later.
    func softDelete(id: String) throws {
        guard let entity = try fetchEntity(id: id) else {
            throw RepositoryError.recordNotFound
        }
        let now = Date()
        entity.deletedAt = now
        entity.updatedAt = now
        try context.save()
    }

    /// Permanently removes an asset's row. Intended for actual file
    /// cleanup scenarios (e.g. purging an already-soft-deleted, no-longer
    /// referenced asset) once the caller has also removed the underlying
    /// file on disk — this only clears the database row.
    func delete(id: String) throws {
        guard let entity = try fetchEntity(id: id) else { return }
        context.delete(entity)
        try context.save()
    }

    /// Permanently removes every asset row — including already soft-deleted
    /// ones, with no other filter. `Asset` rows aren't reachable by
    /// walking the folder/document tree the way `FolderRepository.
    /// hardDeleteAll()`/`DocumentRepository.hardDeleteAll()`'s cascades
    /// are (a `MediaItem` only references an asset by id, and assets can
    /// be shared across items — see this type's doc comment), so a full
    /// account wipe needs this as its own explicit step. Deletes every row
    /// in memory first and commits with a single `context.save()`, rather
    /// than one save per row.
    func hardDeleteAll() throws {
        let request = AssetEntity.fetchRequest()
        let entities = try context.fetch(request)
        guard !entities.isEmpty else { return }
        for entity in entities {
            context.delete(entity)
        }
        try context.save()
    }

    private func fetchEntity(id: String) throws -> AssetEntity? {
        let request = AssetEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func apply(_ asset: Asset, to entity: AssetEntity) {
        entity.id = asset.id
        entity.localPath = asset.localPath
        entity.mimeType = asset.mimeType
        entity.fileName = asset.fileName
        entity.fileSize = asset.fileSize.map { NSNumber(value: $0) }
        entity.contentHash = asset.contentHash
        entity.createdAt = asset.createdAt
        entity.updatedAt = asset.updatedAt
        entity.deletedAt = asset.deletedAt
    }
}

private extension Asset {
    init(entity: AssetEntity) {
        self.init(
            id: entity.id ?? "",
            localPath: entity.localPath ?? "",
            mimeType: entity.mimeType ?? "",
            fileName: entity.fileName ?? "",
            fileSize: entity.fileSize?.intValue,
            contentHash: entity.contentHash,
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date(),
            deletedAt: entity.deletedAt
        )
    }
}
