import CoreData

/// Builds the `NSMappingModel` that migrates a pre-NO-005 store (`Folder`
/// / `Document` / `DocumentBlock`) to the NO-005 schema (`Folder` /
/// `Document` / `DocumentItem` / `TextItem` / `TextMark` / `Asset` /
/// `MediaItem`) — `tasks/NO-005.md` §4.1, §5.
///
/// **Why this is built in code instead of an `.xcmappingmodel` project
/// resource:** `.xcmappingmodel` files are serialized by Xcode's Mapping
/// Model GUI editor into a format meant to be authored through that
/// editor, not hand-written as text (unlike `.xcdatamodel/contents`,
/// which is plain, hand-editable XML). `NSMappingModel`'s public API
/// covers exactly the same ground — per-entity attribute/relationship
/// mappings, plus a custom `NSEntityMigrationPolicy` class for the one
/// entity that needs one — and is fully supported for a
/// programmatically-driven migration. This is a deliberate deviation from
/// the brief; see this feature's final report for the reasoning.
///
/// `Folder`'s and `Document`'s attribute/relationship mappings are built
/// on top of `NSMappingModel.inferredMappingModel(forSourceModel:
/// destinationModel:)` — both entities are otherwise structurally
/// unchanged (`Folder`) or additive (`Document` only gains
/// `schemaVersion`/`revision`), so Core Data's own inference already
/// produces correct `$source.<attr>` / relationship-lookup expressions
/// for them; only `Document`'s two new attributes need filling in by
/// hand. `DocumentBlock` → `DocumentItem` is the one entity mapping that
/// can't be inferred (its `contentJSON` fans out into `TextItem` +
/// `TextMark` rows) and is built from scratch with
/// `DocumentBlockMigrationPolicy`.
enum SemiboldMigrationMapping {
    /// Entity mapping names, exposed for anything that later needs to
    /// resolve another entity's destination instance via
    /// `NSMigrationManager.destinationInstances(forEntityMappingName:
    /// sourceInstances:)`.
    enum MappingName {
        static let documentBlockToDocumentItem = "DocumentBlockToDocumentItem"
    }

    /// Builds the full mapping model. Throws only if Core Data's own
    /// inference fails to produce the `Folder`/`Document` mappings this
    /// relies on (e.g. the two model versions no longer match the shapes
    /// this file assumes).
    static func make(
        sourceModel: NSManagedObjectModel,
        destinationModel: NSManagedObjectModel
    ) throws -> NSMappingModel {
        let inferred = try NSMappingModel.inferredMappingModel(
            forSourceModel: sourceModel,
            destinationModel: destinationModel
        )

        guard let folderMapping = inferred.entityMappings.first(where: { $0.sourceEntityName == "Folder" }),
              let documentMapping = inferred.entityMappings.first(where: { $0.sourceEntityName == "Document" }) else {
            throw MappingError.missingInferredMapping
        }

        // `Document` gains `schemaVersion`/`revision` in NO-005 §3 — every
        // migrated Document starts at 1 for both (there's no earlier
        // schemaVersion to carry forward, and NO-005 only adds the
        // revision counter, it doesn't backfill a change history for it).
        var documentAttributes = documentMapping.attributeMappings ?? []
        documentAttributes.append(constantAttribute("schemaVersion", value: 1))
        documentAttributes.append(constantAttribute("revision", value: 1))
        documentMapping.attributeMappings = documentAttributes

        // `Document.items` (→ DocumentItem) has no inverse and is left
        // unmapped here on purpose: DocumentItem's canonical link back to
        // its Document is the flat `documentId` string
        // `DocumentBlockMigrationPolicy` sets, matching
        // `STORAGE_ARCHITECTURE.md` §5's flat-FK batch-query design
        // rather than an object-graph relationship. `blocks` (→
        // DocumentBlock) has no destination counterpart at all — every
        // DocumentBlock becomes a DocumentItem via the custom mapping
        // below instead.

        let documentBlockMapping = try documentBlockToDocumentItemMapping(
            sourceModel: sourceModel,
            destinationModel: destinationModel
        )

        let mappingModel = NSMappingModel()
        mappingModel.entityMappings = [folderMapping, documentMapping, documentBlockMapping]
        return mappingModel
    }

    private static func documentBlockToDocumentItemMapping(
        sourceModel: NSManagedObjectModel,
        destinationModel: NSManagedObjectModel
    ) throws -> NSEntityMapping {
        guard let sourceEntity = sourceModel.entitiesByName["DocumentBlock"],
              let destinationEntity = destinationModel.entitiesByName["DocumentItem"] else {
            throw MappingError.missingInferredMapping
        }

        let mapping = NSEntityMapping()
        mapping.name = MappingName.documentBlockToDocumentItem
        mapping.mappingType = .customEntityMappingType
        mapping.sourceEntityName = sourceEntity.name
        mapping.destinationEntityName = destinationEntity.name
        mapping.sourceEntityVersionHash = sourceEntity.versionHash
        mapping.destinationEntityVersionHash = destinationEntity.versionHash
        mapping.entityMigrationPolicyClassName = String(reflecting: DocumentBlockMigrationPolicy.self)
        // Tells `NSMigrationManager` which source rows to hand to
        // `DocumentBlockMigrationPolicy` — without this, a custom entity
        // mapping has no source instances to iterate at all (this is the
        // same `FETCH(...)` shape Core Data's own inferred mapping models
        // generate for every other entity mapping).
        mapping.sourceExpression = NSExpression(
            format: "FETCH(FUNCTION($manager, \"fetchRequestForSourceEntityNamed:predicateString:\", %@, %@), "
                + "FUNCTION($manager, \"sourceContext\"), NO)",
            sourceEntity.name ?? "DocumentBlock",
            "TRUEPREDICATE"
        )
        // No attribute/relationship mappings: `DocumentBlockMigrationPolicy
        // .createDestinationInstances` sets every DocumentItem field
        // itself, plus the TextItem/TextMark rows it fans out to.
        // DocumentItem/TextItem/TextMark declare no Core Data
        // relationships at all, so there's no relationship-creation pass
        // to configure here either.
        return mapping
    }

    private static func constantAttribute(_ name: String, value: Int) -> NSPropertyMapping {
        let mapping = NSPropertyMapping()
        mapping.name = name
        mapping.valueExpression = NSExpression(forConstantValue: NSNumber(value: value))
        return mapping
    }

    enum MappingError: Error {
        case missingInferredMapping
    }
}
