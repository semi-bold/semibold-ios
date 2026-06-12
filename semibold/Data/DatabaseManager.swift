import Foundation
import GRDB

/// Owns the app's single SQLite connection and keeps its schema up to
/// date.
///
/// semi:bold stores everything locally — folders, documents, and the
/// blocks that make up a document's content — in one on-device database.
/// `DatabaseManager` is the one place that knows where that database file
/// lives and how its schema has evolved over time, so the rest of the app
/// can read/write through GRDB without worrying about setup or upgrades.
final class DatabaseManager {
    /// Shared instance used across the app (and previews/tests can create
    /// their own via `init(path:)`).
    static let shared = DatabaseManager()

    /// The underlying GRDB connection. All repositories read/write
    /// through this queue.
    let dbQueue: DatabaseQueue

    /// Creates the manager, opening (or creating) the database file at
    /// `path` and bringing its schema up to the latest version.
    ///
    /// - Parameter path: Location of the SQLite file. Defaults to
    ///   `semibold.sqlite` inside the app's Application Support
    ///   directory. Pass an in-memory path (e.g. `":memory:"`) for tests
    ///   and previews.
    init(path: String = DatabaseManager.defaultDatabasePath()) {
        do {
            dbQueue = try DatabaseQueue(path: path)
            try AppMigrations.migrator.migrate(dbQueue)
        } catch {
            // The local database is required for the app to function;
            // if it can't be opened or migrated there's nothing
            // meaningful to fall back to.
            fatalError("Failed to set up local database: \(error)")
        }
    }

    /// Default on-disk location for the local database: a
    /// `semibold.sqlite` file inside the app's Application Support
    /// directory, creating that directory if it doesn't exist yet.
    static func defaultDatabasePath() -> String {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try? fileManager.createDirectory(
                at: appSupportURL,
                withIntermediateDirectories: true
            )
        }

        return appSupportURL.appendingPathComponent("semibold.sqlite").path
    }
}
