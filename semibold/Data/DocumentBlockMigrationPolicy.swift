import CoreData
import Foundation

/// Fans a single pre-NO-005 `DocumentBlock` row out into the new schema's
/// `DocumentItem` (position/hierarchy) + `TextItem` (text) + zero or more
/// `TextMark` (inline formatting) rows — run once per source block by
/// `NSMigrationManager` while opening a store still on the old schema
/// (`tasks/NO-005.md` §4.1, §5 "Custom Migration Policy 실행").
///
/// A `DocumentBlock` mixes structure (its position/parent) and content
/// (its rich-text spans) in one `contentJSON` blob; the new schema splits
/// that into a bare `DocumentItem` plus a type-specific detail row
/// (`STORAGE_ARCHITECTURE.md` §2's "구조와 실제 콘텐츠의 분리"). Turning one
/// `DocumentBlock` into up to `1 + 1 + N` destination rows is a fan-out
/// Lightweight Migration can't express, hence this custom policy.
///
/// `DocumentItem`/`TextItem`/`TextMark` declare no Core Data
/// relationships at all (`SemiboldModel 2.xcdatamodel` — they link back
/// via flat `documentId`/`parentItemId`/`itemId` string columns, the
/// canonical FK per the prior NO-005 model-version commit), so this is
/// the *only* place that needs to run for this entity mapping — there's
/// no separate relationship-creation pass to configure in
/// `SemiboldMigrationMapping`.
final class DocumentBlockMigrationPolicy: NSEntityMigrationPolicy {
    override func createDestinationInstances(
        forSource sInstance: NSManagedObject,
        in mapping: NSEntityMapping,
        manager: NSMigrationManager
    ) throws {
        let destinationContext = manager.destinationContext

        let blockId = (sInstance.value(forKey: "id") as? String) ?? UUID().uuidString
        let sortOrder = (sInstance.value(forKey: "sortOrder") as? Int64) ?? 0
        let typeRaw = sInstance.value(forKey: "type") as? String
        let contentJSON = (sInstance.value(forKey: "contentJSON") as? String) ?? ""
        let createdAt = sInstance.value(forKey: "createdAt") as? Date
        let updatedAt = sInstance.value(forKey: "updatedAt") as? Date
        let deletedAt = sInstance.value(forKey: "deletedAt") as? Date

        let documentId = (sInstance.value(forKey: "document") as? NSManagedObject)?.value(forKey: "id") as? String
        let parentItemId = (sInstance.value(forKey: "parent") as? NSManagedObject)?.value(forKey: "id") as? String

        // DocumentItem — position/hierarchy only (STORAGE_ARCHITECTURE.md §3.2).
        let documentItem = NSEntityDescription.insertNewObject(forEntityName: "DocumentItem", into: destinationContext)
        documentItem.setValue(blockId, forKey: "id")
        documentItem.setValue(documentId, forKey: "documentId")
        documentItem.setValue(parentItemId, forKey: "parentItemId")
        documentItem.setValue("text", forKey: "contentType")
        documentItem.setValue(OrderKey.fromLegacySortOrder(sortOrder), forKey: "orderKey")
        documentItem.setValue(Int64(1), forKey: "revision")
        documentItem.setValue(createdAt, forKey: "createdAt")
        documentItem.setValue(updatedAt, forKey: "updatedAt")
        documentItem.setValue(deletedAt, forKey: "deletedAt")

        // TextItem — 1:1 with the DocumentItem above via `itemId` == its `id`.
        let textItem = NSEntityDescription.insertNewObject(forEntityName: "TextItem", into: destinationContext)
        textItem.setValue(blockId, forKey: "itemId")

        if let blockType = typeRaw.flatMap(BlockType.init(rawValue:)) {
            let content = BlockContent.decode(from: contentJSON, type: blockType)
            let decomposition = TextDecomposition.decompose(content)

            textItem.setValue(Self.textKind(for: blockType), forKey: "textKind")
            textItem.setValue(decomposition.plainText, forKey: "plainText")
            textItem.setValue(Self.headingLevel(for: content), forKey: "headingLevel")
            textItem.setValue(Self.isChecked(for: content), forKey: "isChecked")
            // `alignment`/`customStyleId` have no equivalent in the pre-NO-005
            // block model, so every migrated block leaves them unset.

            // TextMark — one row per inline mark BlockContent recorded.
            for mark in decomposition.marks {
                let textMark = NSEntityDescription.insertNewObject(forEntityName: "TextMark", into: destinationContext)
                textMark.setValue(UUID().uuidString, forKey: "id")
                textMark.setValue(blockId, forKey: "itemId")
                textMark.setValue(Int64(mark.startOffset), forKey: "startOffset")
                textMark.setValue(Int64(mark.endOffset), forKey: "endOffset")
                textMark.setValue(mark.markType, forKey: "markType")
                textMark.setValue(mark.valueMode, forKey: "valueMode")
                textMark.setValue(mark.valueText, forKey: "valueText")
            }
        } else {
            // An unrecognized/legacy `type` string can't be safely
            // reinterpreted as any known `BlockType` — decoding its
            // `contentJSON` against the wrong shape (e.g. `.paragraph`'s
            // `{type, text}`) would silently produce an empty result and
            // lose the block's real content. Per `tasks/NO-005.md` §7
            // "알 수 없는 contentType을 만난 경우: 임의로 삭제하지 않고
            // 읽기 전용으로 보존", preserve the untouched, raw
            // `contentJSON` as `plainText` instead, and mark the kind as
            // `"unknown"` so the editor can render it read-only rather
            // than mistaking it for real paragraph text. Mark
            // decomposition is skipped — there's no reliable shape to
            // parse offsets/marks out of.
            textItem.setValue("unknown", forKey: "textKind")
            textItem.setValue(contentJSON, forKey: "plainText")
            textItem.setValue(nil, forKey: "headingLevel")
            textItem.setValue(nil, forKey: "isChecked")
        }

        // Required so `NSMigrationManager` can resolve "the DocumentItem
        // this DocumentBlock became" if a later entity mapping ever needs
        // to look it up (and so migration-progress bookkeeping sees this
        // source instance as handled).
        manager.associate(sourceInstance: sInstance, withDestinationInstance: documentItem, for: mapping)
    }

    /// Maps a `BlockType` to the new schema's `TextItem.textKind`.
    ///
    /// `DOCUMENT_MODEL.md` §4.1 only lists `paragraph`/`heading`/`quote`/
    /// `checklist`/`caption` as *recommended* kinds, not an exhaustive
    /// enum, so `blockquote`/`checklistItem` are renamed to match that
    /// list's naming exactly, while the remaining `BlockType`s (list
    /// items, code block, divider — outside that recommended set) keep
    /// their existing `BlockType` raw value rather than inventing new
    /// names `tasks/NO-005.md` doesn't specify.
    private static func textKind(for blockType: BlockType) -> String {
        switch blockType {
        case .paragraph: return "paragraph"
        case .heading: return "heading"
        case .blockquote: return "quote"
        case .checklistItem: return "checklist"
        case .bulletedListItem: return "bulleted_list_item"
        case .numberedListItem: return "numbered_list_item"
        case .codeBlock: return "code_block"
        case .divider: return "divider"
        }
    }

    private static func headingLevel(for content: BlockContent) -> Int64? {
        guard case .heading(let heading) = content else { return nil }
        return Int64(heading.level)
    }

    private static func isChecked(for content: BlockContent) -> Bool? {
        guard case .checklistItem(let checklist) = content else { return nil }
        return checklist.checked
    }
}
