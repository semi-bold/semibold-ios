import CoreData

extension NSManagedObjectContext {
    /// Runs `body` — typically several repository mutations, each called
    /// with `save: false` — then commits everything they touched in a
    /// single `save()`.
    ///
    /// Core Data's `save()` is the transaction-commit boundary: one call
    /// atomically persists every pending change in this context as one
    /// Persistent History entry. Letting each repository method save on
    /// its own turns one logical edit into several separate commits —
    /// `STORAGE_ARCHITECTURE.md` §6 requires the opposite ("콘텐츠
    /// 생성·수정은 하나의 트랜잭션에서 처리한다... 중간 실패 시 모든 변경을
    /// 롤백한다"), and a crash between those separate commits could leave
    /// related rows (e.g. a `DocumentItem` and its `TextItem` detail row)
    /// only half-written.
    @discardableResult
    func withTransaction<T>(_ body: () throws -> T) throws -> T {
        let result = try body()
        try save()
        return result
    }
}
