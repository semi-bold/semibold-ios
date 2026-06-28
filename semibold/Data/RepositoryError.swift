import Foundation

/// Errors the Core Data-backed repositories throw for failure paths that
/// previously surfaced as GRDB's `PersistenceError.recordNotFound` (e.g.
/// updating a row that has since been removed out from under the
/// caller).
enum RepositoryError: Error {
    case recordNotFound
}
