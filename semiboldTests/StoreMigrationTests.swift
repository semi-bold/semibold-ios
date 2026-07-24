import CoreData
import Testing

@testable import semibold

/// Drives the real `StoreMigrationCoordinator.migrateStoreIfNeeded` path
/// against a hand-built pre-NO-005 store (`Folder`/`Document`/
/// `DocumentBlock`, the schema before this work-code) and checks the
/// NO-005 schema it produces (`Document`/`DocumentItem`/`TextItem`/
/// `TextMark`) — `tasks/NO-005.md` §4.1 "Core Data 마이그레이션", §4.2
/// "DocumentBlock.contentJSON 분해 규칙", §5 "마이그레이션 플로우", this
/// feature's AC8.
///
/// Unlike every other Core Data test in this target (`CoreDataTestStore`'s
/// `NSInMemoryStoreType`), this seeds and migrates a real on-disk SQLite
/// file in a throwaway temp directory. `NSMigrationManager` and
/// `StoreMigrationCoordinator` both operate on store *files*
/// (`NSPersistentStoreCoordinator.metadataForPersistentStore(at:)`, a
/// staging-file swap, `-wal`/`-shm` sidecars) — none of which an
/// in-memory store has, so this is the one place in the suite that needs
/// to touch disk.
struct StoreMigrationTests {
    /// Fixed sample content shared between the seeding step (building the
    /// pre-migration `contentJSON`) and the assertions (computing the
    /// expected post-migration `plainText`/`TextMark` offsets) — kept as
    /// named pieces rather than one literal string so the offset math in
    /// the test reads as "sum of the pieces before this one", not magic
    /// numbers.
    private enum Fixture {
        static let folderName = "Trip Planning"
        static let documentTitle = "Packing Notes"
        static let headingText = "Trip Overview"
        static let introText = "Remember to pack "
        static let boldWord = "passport"
        static let middleText = " and "
        static let italicWord = "sunscreen"
        static let tailText = ", or check the "
        static let linkLabel = "packing guide"
        static let linkURL = "https://example.com/packing"
        static let finalPunctuation = "."
        static let listParentText = "Packing list"
        static let listChildText = "Passport"
        static let checklistText = "Buy sunscreen"
    }

    /// The ids of everything `seedLegacyStore()` inserted, so the
    /// post-migration assertions can look each row up by the id it had
    /// *before* migrating rather than guessing.
    private struct SeededStore {
        var storeURL: URL
        var tempDirectory: URL
        var folderId: String
        var documentId: String
        var headingBlockId: String
        var formattedBlockId: String
        var listParentBlockId: String
        var listChildBlockId: String
        var checklistBlockId: String
    }

    // MARK: - Legacy (pre-NO-005) store setup

    /// Loads the pre-NO-005 model version by name directly out of the
    /// compiled `SemiboldModel.momd` (`SemiboldModel.mom` — the version
    /// `.xccurrentversion` pointed at before this feature added
    /// `SemiboldModel 2`), rather than `DatabaseManager.model` (which
    /// always resolves to whichever version is *current*).
    private func legacyModel() throws -> NSManagedObjectModel {
        let momdURL = try #require(
            Bundle(for: DatabaseManager.self).url(forResource: "SemiboldModel", withExtension: "momd")
        )
        return try #require(
            NSManagedObjectModel(contentsOf: momdURL.appendingPathComponent("SemiboldModel.mom"))
        )
    }

    /// A fresh, empty temp directory to hold one test's store file (plus
    /// whatever backup/staging sidecars `StoreMigrationCoordinator`
    /// creates next to it).
    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Loads (creating if needed) a persistent store at `storeURL` under
    /// `model`, synchronously (safe for a local SQLite store — see
    /// `DatabaseManager.init`'s equivalent comment).
    private func openStore(model: NSManagedObjectModel, storeURL: URL) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "SemiboldModel", managedObjectModel: model)
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    private func insertLegacyFolder(id: String, name: String, into context: NSManagedObjectContext, at date: Date) -> NSManagedObject {
        let folder = NSEntityDescription.insertNewObject(forEntityName: "Folder", into: context)
        folder.setValue(id, forKey: "id")
        folder.setValue(name, forKey: "name")
        folder.setValue(Int64(0), forKey: "sortOrder")
        folder.setValue(date, forKey: "createdAt")
        folder.setValue(date, forKey: "updatedAt")
        return folder
    }

    private func insertLegacyDocument(
        id: String,
        title: String,
        folder: NSManagedObject,
        into context: NSManagedObjectContext,
        at date: Date
    ) -> NSManagedObject {
        let document = NSEntityDescription.insertNewObject(forEntityName: "Document", into: context)
        document.setValue(id, forKey: "id")
        document.setValue(title, forKey: "title")
        document.setValue(Int64(0), forKey: "sortOrder")
        document.setValue(date, forKey: "createdAt")
        document.setValue(date, forKey: "updatedAt")
        document.setValue(folder, forKey: "folder")
        return document
    }

    /// Inserts one pre-NO-005 `DocumentBlock` row directly against the
    /// legacy model, via plain KVC — matching how
    /// `DocumentBlockMigrationPolicy` itself reads source rows, and
    /// sidestepping the fact that the compiled `DocumentBlockEntity` class
    /// no longer exists now that `DocumentBlock` isn't in the *current*
    /// model version.
    @discardableResult
    private func insertLegacyBlock(
        id: String,
        sortOrder: Int64,
        typeRaw: String,
        contentJSON: String,
        document: NSManagedObject,
        parent: NSManagedObject?,
        into context: NSManagedObjectContext,
        at date: Date
    ) -> NSManagedObject {
        let block = NSEntityDescription.insertNewObject(forEntityName: "DocumentBlock", into: context)
        block.setValue(id, forKey: "id")
        block.setValue(sortOrder, forKey: "sortOrder")
        block.setValue(typeRaw, forKey: "type")
        block.setValue(contentJSON, forKey: "contentJSON")
        block.setValue(date, forKey: "createdAt")
        block.setValue(date, forKey: "updatedAt")
        block.setValue(document, forKey: "document")
        if let parent {
            block.setValue(parent, forKey: "parent")
        }
        return block
    }

    /// Builds a pre-NO-005 store with 1 `Folder`, 1 `Document`, and 5
    /// `DocumentBlock`s covering: a plain heading, a paragraph with three
    /// different inline marks (bold/italic/link), a nested pair of
    /// bulleted list items (to exercise `parentItemId`), and a checked
    /// checklist item (`isChecked`) — everything AC8 asks for, plus the
    /// hierarchy/formatting edge cases `DocumentBlockMigrationPolicy`
    /// specifically handles.
    private func seedLegacyStore() throws -> SeededStore {
        let tempDirectory = try makeTempDirectory()
        let storeURL = tempDirectory.appendingPathComponent("legacy.sqlite")
        let container = try openStore(model: try legacyModel(), storeURL: storeURL)
        let context = container.viewContext
        let now = Date()

        let folderId = UUID().uuidString
        let folder = insertLegacyFolder(id: folderId, name: Fixture.folderName, into: context, at: now)

        let documentId = UUID().uuidString
        let document = insertLegacyDocument(id: documentId, title: Fixture.documentTitle, folder: folder, into: context, at: now)

        let headingBlockId = UUID().uuidString
        insertLegacyBlock(
            id: headingBlockId,
            sortOrder: 0,
            typeRaw: BlockType.heading.rawValue,
            contentJSON: BlockContent.heading(
                HeadingContent(level: 2, text: [RichTextSpan(text: Fixture.headingText)])
            ).encodeJSON(),
            document: document,
            parent: nil,
            into: context,
            at: now
        )

        let formattedBlockId = UUID().uuidString
        insertLegacyBlock(
            id: formattedBlockId,
            sortOrder: 1,
            typeRaw: BlockType.paragraph.rawValue,
            contentJSON: BlockContent.paragraph(
                ParagraphContent(text: [
                    RichTextSpan(text: Fixture.introText),
                    RichTextSpan(text: "**\(Fixture.boldWord)**", marks: [.bold]),
                    RichTextSpan(text: Fixture.middleText),
                    RichTextSpan(text: "*\(Fixture.italicWord)*", marks: [.italic]),
                    RichTextSpan(text: Fixture.tailText),
                    RichTextSpan(text: "[\(Fixture.linkLabel)](\(Fixture.linkURL))", marks: [.link], href: Fixture.linkURL),
                    RichTextSpan(text: Fixture.finalPunctuation)
                ])
            ).encodeJSON(),
            document: document,
            parent: nil,
            into: context,
            at: now
        )

        let listParentBlockId = UUID().uuidString
        let listParentBlock = insertLegacyBlock(
            id: listParentBlockId,
            sortOrder: 2,
            typeRaw: BlockType.bulletedListItem.rawValue,
            contentJSON: BlockContent.bulletedListItem(
                ListItemContent(type: "bulleted_list_item", text: [RichTextSpan(text: Fixture.listParentText)])
            ).encodeJSON(),
            document: document,
            parent: nil,
            into: context,
            at: now
        )

        let listChildBlockId = UUID().uuidString
        insertLegacyBlock(
            id: listChildBlockId,
            sortOrder: 0,
            typeRaw: BlockType.bulletedListItem.rawValue,
            contentJSON: BlockContent.bulletedListItem(
                ListItemContent(type: "bulleted_list_item", text: [RichTextSpan(text: Fixture.listChildText)])
            ).encodeJSON(),
            document: document,
            parent: listParentBlock,
            into: context,
            at: now
        )

        let checklistBlockId = UUID().uuidString
        insertLegacyBlock(
            id: checklistBlockId,
            sortOrder: 3,
            typeRaw: BlockType.checklistItem.rawValue,
            contentJSON: BlockContent.checklistItem(
                ChecklistItemContent(checked: true, text: [RichTextSpan(text: Fixture.checklistText)])
            ).encodeJSON(),
            document: document,
            parent: nil,
            into: context,
            at: now
        )

        try context.save()

        // Release the legacy container's connection to `storeURL` before
        // handing the file off to `StoreMigrationCoordinator` — it reads
        // (and later replaces) that file directly, the same "one open
        // connection at a time" discipline `DatabaseManager.init` follows
        // in production between session mode switches.
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }

        return SeededStore(
            storeURL: storeURL,
            tempDirectory: tempDirectory,
            folderId: folderId,
            documentId: documentId,
            headingBlockId: headingBlockId,
            formattedBlockId: formattedBlockId,
            listParentBlockId: listParentBlockId,
            listChildBlockId: listChildBlockId,
            checklistBlockId: checklistBlockId
        )
    }

    // MARK: - Tests

    @Test(
        "Migrating a pre-NO-005 store converts 1 Folder + 1 Document + 5 DocumentBlocks into the NO-005 schema, preserving ids, hierarchy, and inline formatting"
    )
    func migratesLegacyDataIntoNewSchema() throws {
        let seeded = try seedLegacyStore()
        defer { try? FileManager.default.removeItem(at: seeded.tempDirectory) }

        try StoreMigrationCoordinator.migrateStoreIfNeeded(
            storeURL: seeded.storeURL,
            destinationModel: DatabaseManager.model
        )

        let migrated = try openStore(model: DatabaseManager.model, storeURL: seeded.storeURL)
        let context = migrated.viewContext

        // Folder: §Decisions "Folder는 변경 없음" — same row, same id.
        let folders = try context.fetch(FolderEntity.fetchRequest())
        #expect(folders.count == 1)
        #expect(folders.first?.id == seeded.folderId)
        #expect(folders.first?.name == Fixture.folderName)

        // Document: same id, keeps its folder link, gains schemaVersion/revision.
        let documents = try context.fetch(DocumentEntity.fetchRequest())
        #expect(documents.count == 1)
        let document = try #require(documents.first)
        #expect(document.id == seeded.documentId)
        #expect(document.title == Fixture.documentTitle)
        #expect(document.folder?.id == seeded.folderId)
        #expect(document.schemaVersion == 1)
        #expect(document.revision == 1)

        // DocumentItem: exactly one per migrated DocumentBlock, id
        // preserved from the source block, correctly linked back to the
        // Document and (where applicable) to its parent item.
        let items = try context.fetch(DocumentItemEntity.fetchRequest())
        #expect(items.count == 5)
        let itemsById = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.id.map { ($0, item) } })
        #expect(itemsById.count == 5) // no id collisions/misattribution

        for item in items {
            #expect(item.documentId == seeded.documentId)
            #expect(item.contentType == "text")
            #expect(item.revision == 1)
        }

        let headingItem = try #require(itemsById[seeded.headingBlockId])
        #expect(headingItem.parentItemId == nil)

        let listParentItem = try #require(itemsById[seeded.listParentBlockId])
        #expect(listParentItem.parentItemId == nil)
        let listChildItem = try #require(itemsById[seeded.listChildBlockId])
        #expect(listChildItem.parentItemId == listParentItem.id)

        // TextItem: 1:1 with each DocumentItem via itemId == the same
        // preserved block id, with the right textKind/headingLevel/
        // isChecked per source block type.
        let textItems = try context.fetch(TextItemEntity.fetchRequest())
        #expect(textItems.count == 5)
        let textItemsByItemId = Dictionary(uniqueKeysWithValues: textItems.compactMap { item in item.itemId.map { ($0, item) } })
        #expect(textItemsByItemId.count == 5)

        let headingText = try #require(textItemsByItemId[seeded.headingBlockId])
        #expect(headingText.textKind == "heading")
        #expect(headingText.plainText == Fixture.headingText)
        #expect(headingText.headingLevel?.intValue == 2)

        let checklistText = try #require(textItemsByItemId[seeded.checklistBlockId])
        #expect(checklistText.textKind == "checklist")
        #expect(checklistText.plainText == Fixture.checklistText)
        #expect(checklistText.isChecked?.boolValue == true)

        let listParentText = try #require(textItemsByItemId[seeded.listParentBlockId])
        #expect(listParentText.textKind == "bulleted_list_item")
        #expect(listParentText.plainText == Fixture.listParentText)

        let listChildText = try #require(textItemsByItemId[seeded.listChildBlockId])
        #expect(listChildText.plainText == Fixture.listChildText)

        // TextMark: the formatted paragraph's bold/italic/link spans,
        // decomposed into offsets over its delimiter-stripped plainText.
        let formattedText = try #require(textItemsByItemId[seeded.formattedBlockId])
        let expectedPlainText = Fixture.introText + Fixture.boldWord + Fixture.middleText
            + Fixture.italicWord + Fixture.tailText + Fixture.linkLabel + Fixture.finalPunctuation
        #expect(formattedText.textKind == "paragraph")
        #expect(formattedText.plainText == expectedPlainText)

        let allMarks = try context.fetch(TextMarkEntity.fetchRequest())
        let formattedMarks = allMarks.filter { $0.itemId == seeded.formattedBlockId }.sorted { $0.startOffset < $1.startOffset }
        #expect(formattedMarks.count == 3)
        for mark in formattedMarks {
            #expect(mark.itemId == seeded.formattedBlockId)
        }

        let boldStart = Fixture.introText.utf16.count
        let boldEnd = boldStart + Fixture.boldWord.utf16.count
        let italicStart = boldEnd + Fixture.middleText.utf16.count
        let italicEnd = italicStart + Fixture.italicWord.utf16.count
        let linkStart = italicEnd + Fixture.tailText.utf16.count
        let linkEnd = linkStart + Fixture.linkLabel.utf16.count

        let bold = try #require(formattedMarks.first { $0.markType == "bold" })
        #expect(Int(bold.startOffset) == boldStart)
        #expect(Int(bold.endOffset) == boldEnd)

        let italic = try #require(formattedMarks.first { $0.markType == "italic" })
        #expect(Int(italic.startOffset) == italicStart)
        #expect(Int(italic.endOffset) == italicEnd)

        let link = try #require(formattedMarks.first { $0.markType == "link" })
        #expect(Int(link.startOffset) == linkStart)
        #expect(Int(link.endOffset) == linkEnd)
        #expect(link.valueMode == "url")
        #expect(link.valueText == Fixture.linkURL)

        // Blocks with no inline formatting produced no TextMark rows at all.
        #expect(allMarks.filter { $0.itemId == seeded.headingBlockId }.isEmpty)
        #expect(allMarks.filter { $0.itemId == seeded.checklistBlockId }.isEmpty)
    }

    /// Nice-to-have alongside AC8's successful-migration case: `tasks/
    /// NO-005.md` §7 "알 수 없는 contentType을 만난 경우" requires an
    /// unrecognized legacy block `type` to be preserved read-only, not
    /// silently dropped or emptied. `DocumentBlock.type` is a plain
    /// (Core Data-unconstrained) `String` column, so a raw value outside
    /// `BlockType`'s cases is cheap to synthesize directly.
    @Test("An unrecognized legacy block type is preserved read-only, not dropped or emptied")
    func migratesUnknownBlockTypeAsReadOnlyContent() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let storeURL = tempDirectory.appendingPathComponent("legacy-unknown.sqlite")

        let container = try openStore(model: try legacyModel(), storeURL: storeURL)
        let context = container.viewContext
        let now = Date()

        let folder = insertLegacyFolder(id: UUID().uuidString, name: "Archive", into: context, at: now)
        let document = insertLegacyDocument(id: UUID().uuidString, title: "Old Widget Doc", folder: folder, into: context, at: now)

        let rawContentJSON = #"{"legacyWidgetPayload":"unsupported shape from a discontinued block type"}"#
        let unknownBlockId = UUID().uuidString
        insertLegacyBlock(
            id: unknownBlockId,
            sortOrder: 0,
            typeRaw: "legacy_widget", // not a case BlockType(rawValue:) can resolve
            contentJSON: rawContentJSON,
            document: document,
            parent: nil,
            into: context,
            at: now
        )

        try context.save()
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }

        try StoreMigrationCoordinator.migrateStoreIfNeeded(storeURL: storeURL, destinationModel: DatabaseManager.model)

        let migrated = try openStore(model: DatabaseManager.model, storeURL: storeURL)
        let textItems = try migrated.viewContext.fetch(TextItemEntity.fetchRequest())
        let unknownTextItem = try #require(textItems.first { $0.itemId == unknownBlockId })

        #expect(unknownTextItem.textKind == "unknown")
        #expect(unknownTextItem.plainText == rawContentJSON)
    }
}
