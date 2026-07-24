import CoreData
import Foundation

/// Pairs a `MediaContent` detail row with the `Asset` it references, the
/// way `STORAGE_ARCHITECTURE.md` §5.4's `media_items JOIN assets` query
/// does. `asset` is `nil` if the referenced asset row can't be found
/// (e.g. it was already purged) — callers decide how to degrade (show a
/// placeholder, etc.) rather than this repository silently hiding a
/// broken reference.
struct MediaContentWithAsset {
    let media: MediaContent
    let asset: Asset?
}

/// Reads and writes `MediaItem` rows — the media-specific detail record
/// for a `DocumentItem` whose `contentType` is `"media"`. Each row is
/// keyed 1:1 off its owning item's id (`itemId`), and points at its file
/// data via `assetId` rather than a Core Data relationship
/// (`STORAGE_ARCHITECTURE.md` §3.6).
///
/// `MediaItem` has no Core Data relationship to `Asset` to traverse (both
/// are flat-FK entities, like every other content table in this
/// migration), so the `resolved` methods below implement
/// `STORAGE_ARCHITECTURE.md` §5.4's SQL join by hand: fetch the media
/// row(s), then fetch the referenced asset row(s) by id. `resolved(itemIds:)`
/// keeps this to exactly two queries total (one for media, one batched
/// `IN` fetch for every distinct asset referenced) no matter how many
/// items are being resolved, rather than one asset lookup per media item.
struct MediaItemRepository {
    let context: NSManagedObjectContext
    private let assetRepository: AssetRepository

    init(context: NSManagedObjectContext = DatabaseManager.sharedOrFallbackContext) {
        self.context = context
        self.assetRepository = AssetRepository(context: context)
    }

    /// Inserts a new media detail row.
    @discardableResult
    func create(_ media: MediaContent) throws -> MediaContent {
        let entity = MediaItemEntity(context: context)
        apply(media, to: entity)
        try context.save()
        return media
    }

    /// Fetches a single item's media detail by its owning `DocumentItem`'s id.
    func find(itemId: String) throws -> MediaContent? {
        try fetchEntity(itemId: itemId).map(MediaContent.init(entity:))
    }

    /// Fetches media detail for several items in a single query — the
    /// batch counterpart to `find(itemId:)`, used internally by
    /// `resolved(itemIds:)` and available directly for callers that don't
    /// need the joined `Asset` data.
    func find(itemIds: [String]) throws -> [MediaContent] {
        guard !itemIds.isEmpty else { return [] }
        let request = MediaItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "itemId IN %@", itemIds)
        return try context.fetch(request).map(MediaContent.init(entity:))
    }

    /// Saves changes to an existing media detail row.
    @discardableResult
    func update(_ media: MediaContent) throws -> MediaContent {
        guard let entity = try fetchEntity(itemId: media.itemId) else {
            throw RepositoryError.recordNotFound
        }
        apply(media, to: entity)
        try context.save()
        return media
    }

    /// Permanently removes a media detail row for direct/standalone use.
    /// As with `TextItemRepository.delete(itemId:)`, everyday content
    /// deletion goes through `DocumentItemRepository` on the owning item;
    /// this does not touch the referenced `Asset` row, since assets can
    /// be shared across multiple media items.
    func delete(itemId: String) throws {
        guard let entity = try fetchEntity(itemId: itemId) else { return }
        context.delete(entity)
        try context.save()
    }

    /// Fetches one item's media detail together with its referenced
    /// asset — the single-item form of the §5.4 join.
    func resolved(itemId: String) throws -> MediaContentWithAsset? {
        guard let media = try find(itemId: itemId) else { return nil }
        let asset = try assetRepository.find(id: media.assetId)
        return MediaContentWithAsset(media: media, asset: asset)
    }

    /// Fetches several items' media detail together with their
    /// referenced assets in two queries total (one `itemId IN` fetch for
    /// the media rows, one `id IN` fetch for every distinct asset they
    /// reference) — the batch form of `STORAGE_ARCHITECTURE.md` §5.4,
    /// avoiding one asset query per media item when rendering a whole
    /// document's worth of media at once.
    func resolved(itemIds: [String]) throws -> [MediaContentWithAsset] {
        let mediaItems = try find(itemIds: itemIds)
        guard !mediaItems.isEmpty else { return [] }
        let assetIds = Array(Set(mediaItems.map(\.assetId)))
        let assetsById = Dictionary(
            uniqueKeysWithValues: try assetRepository.find(ids: assetIds).map { ($0.id, $0) }
        )
        return mediaItems.map { media in
            MediaContentWithAsset(media: media, asset: assetsById[media.assetId])
        }
    }

    private func fetchEntity(itemId: String) throws -> MediaItemEntity? {
        let request = MediaItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "itemId == %@", itemId)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func apply(_ media: MediaContent, to entity: MediaItemEntity) {
        entity.itemId = media.itemId
        entity.assetId = media.assetId
        entity.mediaType = media.mediaType
        entity.altText = media.altText
        entity.captionItemId = media.captionItemId
        entity.width = media.width.map { NSNumber(value: $0) }
        entity.height = media.height.map { NSNumber(value: $0) }
    }
}

private extension MediaContent {
    init(entity: MediaItemEntity) {
        self.init(
            itemId: entity.itemId ?? "",
            assetId: entity.assetId ?? "",
            mediaType: entity.mediaType ?? "image",
            altText: entity.altText,
            captionItemId: entity.captionItemId,
            width: entity.width?.doubleValue,
            height: entity.height?.doubleValue
        )
    }
}
