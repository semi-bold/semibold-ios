import CoreData
import Foundation
import Testing

@testable import semibold

/// Rehearses the NO-005 store migration against a real pre-NO-005 device
/// snapshot instead of `StoreMigrationTests`' hand-built synthetic fixtures
/// — this feature's AC1-3 (`tasks/NO-005.md` §8 Phase 7 "실사용자 데이터
/// 마이그레이션 검증 및 배포", §4.2 "마이그레이션 결과는 ... 마크다운 export
/// 결과를 diff하여 검증한다").
///
/// The snapshot (`.database/cloud.sqlite` + `-wal`/`-shm`, gitignored, copied
/// via the `/sync-data` skill from a real device) holds real personal
/// folder/document/block content. Per this feature's Decision ("실사용자
/// 데이터를 다루므로 원본을 직접 변형하지 않는다 — 반드시 복사본에 대해서만
/// 마이그레이션을 실행한다"), this test only ever touches a throwaway COPY of
/// it, and only ever inspects/reports row COUNTS, ids, block/text kinds, and
/// character-length deltas — never the actual folder names, document titles,
/// or block text. `documentTitle` is deliberately passed as `""` to every
/// `MarkdownExporter.render` call below so a real title is never even read
/// into this test's memory, let alone logged.
///
/// No-ops (skips, not fails) when `.database/cloud.sqlite` isn't present at
/// the repo root — it's gitignored and won't exist in CI or on a machine
/// that hasn't run `/sync-data`, so this must never break the build for
/// anyone without the snapshot.
struct RealDeviceMigrationRehearsalTests {
    // MARK: - Snapshot location

    /// `.database/cloud.sqlite` at the repo root, resolved from this source
    /// file's own compiled path (`semiboldTests/` is always one level below
    /// the repo root) rather than the test runner's working directory,
    /// which Xcode/`xcodebuild` don't guarantee to be the repo root.
    private static var sourceDatabaseURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // semiboldTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent(".database/cloud.sqlite")
    }

    private static var sourceDatabaseExists: Bool {
        FileManager.default.fileExists(atPath: sourceDatabaseURL.path)
    }

    // MARK: - Copying the snapshot

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Copies the real snapshot's main store file and any `-wal`/`-shm`
    /// sidecars it has into `directory`, so everything downstream operates
    /// on a disposable copy — WAL-mode SQLite can hold committed data only
    /// in those sidecars, so skipping them could silently under-count rows
    /// (mirrors `StoreMigrationCoordinator`'s own sidecar-copying pattern).
    private func copySnapshot(to directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let destination = directory.appendingPathComponent("cloud-rehearsal.sqlite")
        try fileManager.copyItem(at: Self.sourceDatabaseURL, to: destination)

        for suffix in ["-wal", "-shm"] {
            let source = URL(fileURLWithPath: Self.sourceDatabaseURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: URL(fileURLWithPath: destination.path + suffix))
        }

        return destination
    }

    // MARK: - Legacy (pre-NO-005) store reading

    /// Loads the pre-NO-005 model version by name directly out of the
    /// compiled `SemiboldModel.momd`, the same approach
    /// `StoreMigrationTests.legacyModel()` uses — `DatabaseManager.model`
    /// always resolves to the *current* version, not this one.
    private func legacyModel() throws -> NSManagedObjectModel {
        let momdURL = try #require(
            Bundle(for: DatabaseManager.self).url(forResource: "SemiboldModel", withExtension: "momd")
        )
        return try #require(
            NSManagedObjectModel(contentsOf: momdURL.appendingPathComponent("SemiboldModel.mom"))
        )
    }

    private func openStore(model: NSManagedObjectModel, storeURL: URL) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "SemiboldModel", managedObjectModel: model)
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    /// One pre-NO-005 `DocumentBlock` row, read via plain KVC against the
    /// legacy model (no compiled `DocumentBlockEntity` class exists in this
    /// build — see `StoreMigrationTests.insertLegacyBlock`'s doc comment for
    /// why).
    private struct LegacyBlockRow {
        var id: String
        var documentId: String
        var sortOrder: Int64
        var typeRaw: String?
        var contentJSON: String
    }

    private struct LegacySnapshotCounts {
        var folderCount: Int
        var documentCount: Int
        var blockCount: Int
    }

    /// Reads every row this rehearsal needs to know about from the
    /// pre-migration store, then releases the store's connection so
    /// `StoreMigrationCoordinator` can take over the same file.
    ///
    /// `topLevelBlocksByDocument` only keeps each document's TOP-LEVEL
    /// blocks (`parentId == nil`), sorted by `sortOrder` — matching
    /// `DetailViewModel.load()`/`MarkdownDocumentExport`'s own real export
    /// path, which only ever renders `DocumentItemRepository.children(
    /// documentId:parentItemId: nil)` (see this feature's final report for
    /// why nested list items are out of scope for this particular
    /// comparison).
    private func readLegacySnapshot(
        storeURL: URL
    ) throws -> (counts: LegacySnapshotCounts, documentIds: [String], topLevelBlocksByDocument: [String: [LegacyBlockRow]]) {
        let container = try openStore(model: try legacyModel(), storeURL: storeURL)
        let context = container.viewContext

        let folderCount = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Folder")).count

        let documents = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Document"))
        let documentIds = documents.compactMap { $0.value(forKey: "id") as? String }

        let blocks = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "DocumentBlock"))
        let blockCount = blocks.count

        var topLevelBlocksByDocument: [String: [LegacyBlockRow]] = [:]
        for block in blocks {
            guard let blockId = block.value(forKey: "id") as? String,
                  let documentObject = block.value(forKey: "document") as? NSManagedObject,
                  let documentId = documentObject.value(forKey: "id") as? String else { continue }
            let parentId = (block.value(forKey: "parent") as? NSManagedObject)?.value(forKey: "id") as? String
            guard parentId == nil else { continue }

            let row = LegacyBlockRow(
                id: blockId,
                documentId: documentId,
                sortOrder: (block.value(forKey: "sortOrder") as? Int64) ?? 0,
                typeRaw: block.value(forKey: "type") as? String,
                contentJSON: (block.value(forKey: "contentJSON") as? String) ?? ""
            )
            topLevelBlocksByDocument[documentId, default: []].append(row)
        }
        for key in topLevelBlocksByDocument.keys {
            topLevelBlocksByDocument[key]?.sort { $0.sortOrder < $1.sortOrder }
        }

        let counts = LegacySnapshotCounts(folderCount: folderCount, documentCount: documentIds.count, blockCount: blockCount)

        // Release the connection before handing the file off to
        // `StoreMigrationCoordinator` — it reads (and later replaces) that
        // file directly, the same "one open connection at a time"
        // discipline `StoreMigrationTests.seedLegacyStore()` follows.
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }

        return (counts, documentIds, topLevelBlocksByDocument)
    }

    // MARK: - Before/after markdown reconstruction (AC3)

    /// The "before" Markdown for one document, built directly from its
    /// pre-migration blocks — WITHOUT running them through the migration.
    /// Each block's `RichTextSpan.text` still carries its own literal
    /// Markdown delimiters pre-migration (`TextDecomposition.decompose`'s
    /// doc comment), so concatenating a block's spans IS the delimiter-
    /// literal Markdown a user would have seen/typed for it — passed
    /// through `MarkdownExporter.render` with empty `marksByItemId` (a
    /// no-op passthrough per `TextMarkdownReconstruction.markdownText`) so
    /// this gets the exact same per-`textKind` line prefix/wrapper logic
    /// (`# `, `- `, `- [ ] `, …) the real post-migration export uses.
    private func beforeMarkdown(blocks: [LegacyBlockRow]) -> String {
        var items: [DocumentItem] = []
        var textContents: [String: TextContent] = [:]

        for block in blocks {
            items.append(
                DocumentItem(
                    id: block.id,
                    documentId: block.documentId,
                    contentType: "text",
                    orderKey: OrderKey.fromLegacySortOrder(block.sortOrder)
                )
            )
            textContents[block.id] = beforeTextContent(for: block)
        }

        return MarkdownExporter.render(documentTitle: "", items: items, textContents: textContents, marksByItemId: [:])
    }

    /// Mirrors `DocumentBlockMigrationPolicy.createDestinationInstances`'s
    /// per-block conversion (kept in sync by hand since that mapping is
    /// private to that type) so this test's "before" reconstruction and the
    /// real migration agree on `textKind`/`headingLevel`/`isChecked` for
    /// every block.
    private func beforeTextContent(for block: LegacyBlockRow) -> TextContent {
        guard let typeRaw = block.typeRaw, let blockType = BlockType(rawValue: typeRaw) else {
            // Unrecognized type: preserved read-only, same fallback
            // `DocumentBlockMigrationPolicy` applies (`tasks/NO-005.md` §7).
            return TextContent(itemId: block.id, textKind: "unknown", plainText: block.contentJSON)
        }

        let content = BlockContent.decode(from: block.contentJSON, type: blockType)
        let plainText = content.text.map(\.text).joined()
        return TextContent(
            itemId: block.id,
            textKind: Self.textKind(for: blockType),
            plainText: plainText,
            headingLevel: Self.headingLevel(for: content),
            isChecked: Self.isChecked(for: content)
        )
    }

    /// Copy of `DocumentBlockMigrationPolicy.textKind(for:)` (private to
    /// that type) — see that type's doc comment for the mapping rationale.
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

    private static func headingLevel(for content: BlockContent) -> Int? {
        guard case .heading(let heading) = content else { return nil }
        return heading.level
    }

    private static func isChecked(for content: BlockContent) -> Bool? {
        guard case .checklistItem(let checklist) = content else { return nil }
        return checklist.checked
    }

    /// The "after" Markdown for one migrated document, read through the
    /// exact same repositories + `MarkdownExporter.render` call
    /// `MarkdownDocumentExport`/`DetailViewModel` use in production.
    private func afterMarkdown(documentId: String, context: NSManagedObjectContext) throws -> String {
        let itemRepository = DocumentItemRepository(context: context)
        let textItemRepository = TextItemRepository(context: context)
        let textMarkRepository = TextMarkRepository(context: context)

        let items = try itemRepository.children(documentId: documentId, parentItemId: nil)
        let textItemIds = items.filter { $0.contentType == "text" }.map(\.id)
        let textContents = Dictionary(
            uniqueKeysWithValues: try textItemRepository.find(itemIds: textItemIds).map { ($0.itemId, $0) }
        )
        let marksByItemId = try textMarkRepository.marks(itemIds: textItemIds)

        return MarkdownExporter.render(documentTitle: "", items: items, textContents: textContents, marksByItemId: marksByItemId)
    }

    // MARK: - The rehearsal

    @Test(
        "Migrating the real device snapshot (.database/cloud.sqlite, gitignored) preserves every Folder/Document/DocumentBlock row and reproduces each document's markdown export unchanged",
        .enabled(if: RealDeviceMigrationRehearsalTests.sourceDatabaseExists)
    )
    func rehearsesMigrationAgainstRealDeviceSnapshot() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let storeURL = try copySnapshot(to: tempDirectory)

        // AC1: run the real migration against a disposable copy — never
        // the original `.database/cloud.sqlite`.
        let (legacyCounts, documentIds, topLevelBlocksByDocument) = try readLegacySnapshot(storeURL: storeURL)
        print(
            "[migration-rehearsal] pre-migration counts — Folder: \(legacyCounts.folderCount), "
                + "Document: \(legacyCounts.documentCount), DocumentBlock: \(legacyCounts.blockCount)"
        )

        // Computed BEFORE migrating, from the untouched legacy rows above.
        var beforeMarkdownByDocumentId: [String: String] = [:]
        for documentId in documentIds {
            beforeMarkdownByDocumentId[documentId] = beforeMarkdown(blocks: topLevelBlocksByDocument[documentId] ?? [])
        }

        try StoreMigrationCoordinator.migrateStoreIfNeeded(storeURL: storeURL, destinationModel: DatabaseManager.model)

        let migrated = try openStore(model: DatabaseManager.model, storeURL: storeURL)
        let context = migrated.viewContext

        // AC2: post-migration row counts vs. the pre-migration counts
        // captured above — no data lost across the migration.
        let folderCountAfter = try context.fetch(FolderEntity.fetchRequest()).count
        let documentCountAfter = try context.fetch(DocumentEntity.fetchRequest()).count
        let documentItemCountAfter = try context.fetch(DocumentItemEntity.fetchRequest()).count
        print(
            "[migration-rehearsal] post-migration counts — Folder: \(folderCountAfter), "
                + "Document: \(documentCountAfter), DocumentItem: \(documentItemCountAfter)"
        )

        #expect(folderCountAfter == legacyCounts.folderCount, "Folder row count changed across migration")
        #expect(documentCountAfter == legacyCounts.documentCount, "Document row count changed across migration")
        let itemCountMismatchMessage = "DocumentItem row count doesn't exactly match the original DocumentBlock count — "
            + "DocumentBlockMigrationPolicy is designed as a 1:1 mapping, so any difference here is a real finding"
        #expect(documentItemCountAfter == legacyCounts.blockCount, Comment(rawValue: itemCountMismatchMessage))

        // AC3: before/after markdown export diff per document — structural
        // facts only (ids, lengths, block kinds) are ever printed, never
        // the matched/mismatched text itself.
        var mismatchedDocumentCount = 0
        for documentId in documentIds {
            let beforeText = beforeMarkdownByDocumentId[documentId] ?? ""
            let afterText = try afterMarkdown(documentId: documentId, context: context)
            let matched = beforeText == afterText

            if !matched {
                mismatchedDocumentCount += 1
                let blockTypesInvolved = Set((topLevelBlocksByDocument[documentId] ?? []).map { $0.typeRaw ?? "unknown" })
                print(
                    "[migration-rehearsal] markdown export MISMATCH — document \(documentId): "
                        + "before length \(beforeText.utf16.count), after length \(afterText.utf16.count), "
                        + "block types involved: \(blockTypesInvolved.sorted())"
                )
            }

            let mismatchMessage = "Markdown export changed across migration for document \(documentId) "
                + "(see the rehearsal log above for structural details — content itself is never printed)"
            #expect(matched, Comment(rawValue: mismatchMessage))
        }
        print(
            "[migration-rehearsal] markdown export comparison — \(documentIds.count) documents checked, "
                + "\(mismatchedDocumentCount) mismatched"
        )
    }
}
