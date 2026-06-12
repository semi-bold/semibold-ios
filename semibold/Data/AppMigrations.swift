import GRDB

/// Registers every schema change ever made to the local database, in
/// order.
///
/// Each migration is identified by a stable name and runs exactly once
/// per database file — GRDB tracks which migrations have already applied
/// and runs only the new ones. To change the schema, add a new migration
/// here rather than editing an existing one.
enum AppMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_createCoreTables") { db in
            // Folders organize documents into a tree. `parentId` is nil
            // for top-level folders.
            try db.create(table: "folders") { table in
                table.column("id", .text).primaryKey()
                table.column("parentId", .text)
                    .references("folders", onDelete: .none)
                table.column("name", .text).notNull()
                table.column("sortOrder", .integer).notNull().defaults(to: 0)
                table.column("createdAt", .text).notNull()
                table.column("updatedAt", .text).notNull()
                table.column("deletedAt", .text)
            }

            // Documents live inside a folder (or at the root when
            // `folderId` is nil) and hold the user's written content as
            // an ordered tree of blocks.
            try db.create(table: "documents") { table in
                table.column("id", .text).primaryKey()
                table.column("folderId", .text)
                    .references("folders", onDelete: .none)
                table.column("title", .text).notNull().defaults(to: "Untitled")
                table.column("sortOrder", .integer).notNull().defaults(to: 0)
                table.column("createdAt", .text).notNull()
                table.column("updatedAt", .text).notNull()
                table.column("deletedAt", .text)
            }

            // Each block is one paragraph/heading/list item/etc. within a
            // document. Blocks form a tree via `parentId` (e.g. list
            // items nested under a list) and are ordered by `sortOrder`
            // within their parent.
            try db.create(table: "document_blocks") { table in
                table.column("id", .text).primaryKey()
                table.column("documentId", .text).notNull()
                    .references("documents", onDelete: .none)
                table.column("parentId", .text)
                    .references("document_blocks", onDelete: .none)
                table.column("sortOrder", .integer).notNull().defaults(to: 0)
                table.column("type", .text).notNull()
                table.column("contentJSON", .text).notNull()
                table.column("markdownSource", .text)
                table.column("createdAt", .text).notNull()
                table.column("updatedAt", .text).notNull()
                table.column("deletedAt", .text)
            }

            // Recommended indexes (PLANNING §9.4) for the lookups the app
            // performs most often: a folder's children, a folder's
            // documents, and a document's blocks in display order.
            try db.create(
                index: "idx_folders_parent_id",
                on: "folders",
                columns: ["parentId"]
            )
            try db.create(
                index: "idx_documents_folder_id",
                on: "documents",
                columns: ["folderId"]
            )
            try db.create(
                index: "idx_blocks_document_id",
                on: "document_blocks",
                columns: ["documentId"]
            )
            try db.create(
                index: "idx_blocks_parent_id",
                on: "document_blocks",
                columns: ["parentId"]
            )
            try db.create(
                index: "idx_blocks_sort_order",
                on: "document_blocks",
                columns: ["documentId", "parentId", "sortOrder"]
            )
        }

        return migrator
    }
}
