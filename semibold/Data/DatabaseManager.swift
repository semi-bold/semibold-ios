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
    /// Shared instance used across the app, or `nil` if opening/migrating
    /// the on-disk database failed at launch (§15.2 "DB 열기 실패").
    ///
    /// Computed once and cached: if this is `nil`, `openError` holds the
    /// underlying error and the root view shows the
    /// "로컬 저장소를 열 수 없습니다." message instead of `HomeView`
    /// (see `SemiboldApp`/`DatabaseUnavailableView`).
    static let shared: DatabaseManager? = {
        do {
            return try DatabaseManager(path: DatabaseManager.defaultDatabasePath())
        } catch {
            openError = error
            return nil
        }
    }()

    /// The error from opening/migrating the on-disk database, if
    /// `shared` is `nil`. `nil` while the database opened successfully
    /// (the normal case).
    private(set) static var openError: Error?

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
    /// - Throws: if the database file can't be opened or its schema can't
    ///   be migrated to the latest version (§15.2 "DB 열기 실패").
    init(path: String = DatabaseManager.defaultDatabasePath()) throws {
        dbQueue = try DatabaseQueue(path: path)
        try AppMigrations.migrator.migrate(dbQueue)
    }

    /// The connection repositories should default to: `shared`'s queue
    /// when the on-disk database opened successfully, or a throwaway
    /// in-memory queue otherwise.
    ///
    /// This only matters for repositories' default-argument expressions
    /// (`DocumentRepository()`, etc.) — when `shared` is `nil`, the root
    /// view shows `DatabaseUnavailableView` instead of any screen that
    /// would construct a repository, so this fallback queue is never
    /// actually read from or written to in that case. It exists purely so
    /// those default arguments stay non-optional/non-throwing.
    static var sharedOrFallbackQueue: DatabaseQueue {
        if let shared {
            return shared.dbQueue
        }
        // swiftlint:disable:next force_try
        return try! DatabaseQueue()
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
