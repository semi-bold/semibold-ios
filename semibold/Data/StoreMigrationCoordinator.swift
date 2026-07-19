import CoreData
import Foundation

/// Backs up, migrates, and — on failure — rolls back the on-disk Core Data
/// store `DatabaseManager` is about to load, whenever that store is still
/// on a schema version older than `DatabaseManager.model`
/// (`tasks/NO-005.md` §4.1, §5 "마이그레이션 플로우", §7 "예외 처리").
///
/// Pulled out of `DatabaseManager` (rather than inlined in its `init`) so
/// the backup/migrate/rollback sequence has its own testable entry point —
/// a later migration-rehearsal test can drive `migrateStoreIfNeeded`
/// directly against a hand-built pre-NO-005 store file without spinning up
/// the rest of `DatabaseManager`.
///
/// Every step here operates purely on files at `storeURL` and its
/// `-wal`/`-shm` sidecars (the same three-file set `/sync-data` copies for
/// inspection) — nothing here talks to `NSPersistentContainer` or touches
/// `DatabaseManager.shared`.
enum StoreMigrationCoordinator {
    /// Wraps whichever step of the backup/migrate/rollback sequence failed,
    /// so `DatabaseManager.openError` (or a test) can see *why* migration
    /// didn't complete on this launch, per AC7 — this is surfaced exactly
    /// like any other `loadPersistentStores` failure (§15.2 "DB 열기
    /// 실패"), never swallowed.
    enum MigrationError: LocalizedError {
        /// The store's on-disk metadata couldn't be matched to any model
        /// version bundled with the app — nothing to build an
        /// `NSMigrationManager` against.
        case sourceModelUnavailable
        /// Copying the pre-migration store (or a sidecar) to the backup
        /// location failed before any migration was attempted. The
        /// original store at `storeURL` is untouched.
        case backupFailed(underlying: Error)
        /// `NSMigrationManager` failed to produce a destination store.
        /// The original store at `storeURL` was never written to (the
        /// migration ran against a separate staging file), and the backup
        /// step above has already restored/confirmed it as a valid
        /// old-schema store.
        case migrationFailed(underlying: Error)
        /// The migration produced a destination store, but swapping it
        /// into place at `storeURL` (or verifying the swapped-in store
        /// actually opens) failed. The backup has been restored to
        /// `storeURL`, so the person is back on their pre-migration data.
        case storeSwapFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .sourceModelUnavailable:
                return "Couldn't determine the source model version for the existing store."
            case .backupFailed(let underlying):
                return "Couldn't back up the existing store before migrating it: \(underlying.localizedDescription)"
            case .migrationFailed(let underlying):
                return "Store migration failed: \(underlying.localizedDescription)"
            case .storeSwapFailed(let underlying):
                return "Couldn't switch to the migrated store: \(underlying.localizedDescription)"
            }
        }
    }

    /// The `-wal`/`-shm` sidecar suffixes SQLite (and therefore Core Data's
    /// SQLite store type) writes alongside the main store file — same set
    /// `.claude/skills/sync-data/SKILL.md` copies for inspection.
    private static let sidecarSuffixes = ["-wal", "-shm"]

    /// Ensures the persistent store at `storeURL` is loadable with
    /// `destinationModel` before the caller (`DatabaseManager.init`) hands
    /// it to `NSPersistentContainer.loadPersistentStores`.
    ///
    /// No-ops (returns immediately) when:
    /// - no file exists at `storeURL` yet (fresh install — nothing to
    ///   migrate), or
    /// - the existing store's metadata is already compatible with
    ///   `destinationModel` (already migrated, or created fresh at the
    ///   current version).
    ///
    /// Otherwise this runs the full sequence from `tasks/NO-005.md` §5:
    /// back up the pre-migration store, run the custom
    /// `SemiboldMigrationMapping` migration into a staging file, verify the
    /// staging file actually opens, then atomically swap it into place at
    /// `storeURL`. Any failure along the way restores `storeURL` from the
    /// backup this method just made (so the file left behind is always
    /// either the fully-migrated store or the original pre-migration store
    /// — never a partial/corrupted one) and rethrows as `MigrationError`.
    ///
    /// - Parameters:
    ///   - storeURL: The on-disk SQLite store `DatabaseManager` is about to
    ///     load (`local.sqlite` / `cloud.sqlite`).
    ///   - destinationModel: The model version the app should end up
    ///     running against — `DatabaseManager.model` in production.
    ///   - bundle: Where to look up the app's compiled `.momd` model
    ///     versions when resolving the store's *current* (pre-migration)
    ///     model from its metadata. Defaults to the bundle containing
    ///     `DatabaseManager`; tests can override if they load a model from
    ///     elsewhere.
    static func migrateStoreIfNeeded(
        storeURL: URL,
        destinationModel: NSManagedObjectModel,
        bundle: Bundle = Bundle(for: DatabaseManager.self)
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else {
            // Fresh install: NSPersistentContainer will create a brand-new
            // store at the current model version. Nothing to migrate.
            return
        }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL
        )
        if destinationModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
            // Already on the current schema (either migrated on a previous
            // launch, or created fresh at this version already).
            return
        }

        guard let sourceModel = NSManagedObjectModel.mergedModel(from: [bundle], forStoreMetadata: metadata) else {
            throw MigrationError.sourceModelUnavailable
        }

        let backupURL = self.backupURL(for: storeURL)
        do {
            try backupStore(at: storeURL, to: backupURL)
        } catch {
            throw MigrationError.backupFailed(underlying: error)
        }

        let stagingURL = self.stagingURL(for: storeURL)
        removeStoreFiles(at: stagingURL) // clear any leftover staging file from a prior interrupted attempt

        do {
            let mappingModel = try SemiboldMigrationMapping.make(
                sourceModel: sourceModel,
                destinationModel: destinationModel
            )
            let migrationManager = NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel)
            try migrationManager.migrateStore(
                from: storeURL,
                sourceType: NSSQLiteStoreType,
                options: nil,
                with: mappingModel,
                toDestinationURL: stagingURL,
                destinationType: NSSQLiteStoreType,
                destinationOptions: nil
            )
        } catch {
            removeStoreFiles(at: stagingURL)
            // `storeURL` was only ever read from during migration, never
            // written to, so this restore is a defensive no-op in
            // practice — but it keeps this failure path going through the
            // same, single rollback routine every other failure path uses
            // (AC7 "롤백하는 경로가 구현되어 있고").
            try? restoreBackup(from: backupURL, to: storeURL)
            throw MigrationError.migrationFailed(underlying: error)
        }

        do {
            try swapInMigratedStore(from: stagingURL, to: storeURL)
            // Confirm the swapped-in file is actually loadable before
            // declaring success — otherwise a migration that "succeeded"
            // but produced an unopenable store would only surface as a
            // failure on the caller's later `loadPersistentStores` call,
            // by which point it's too late for this method to roll back.
            try verifyStoreLoads(at: storeURL, model: destinationModel)
        } catch {
            removeStoreFiles(at: stagingURL)
            try? restoreBackup(from: backupURL, to: storeURL)
            throw MigrationError.storeSwapFailed(underlying: error)
        }

        // Migration verified end-to-end: the backup has done its job for
        // this launch. Remove it so a person who migrates repeatedly across
        // app updates doesn't accumulate stale pre-migration snapshots
        // forever — if a *future* migration ever fails, `backupStore`
        // below makes a fresh one from the (now current) store before that
        // attempt runs.
        removeStoreFiles(at: backupURL)
    }

    /// Copies `storeURL` and any `-wal`/`-shm` sidecars it has to
    /// `backupURL`, overwriting whatever backup (if any) is already there.
    /// Overwriting is safe here: this only runs once `storeURL` has been
    /// confirmed to still be a valid pre-migration store (the
    /// `isConfiguration(withName:compatibleWithStoreMetadata:)` check in
    /// `migrateStoreIfNeeded` above), so a fresh backup is always at least
    /// as good as whatever stale one preceded it.
    private static func backupStore(at storeURL: URL, to backupURL: URL) throws {
        let fileManager = FileManager.default
        removeStoreFiles(at: backupURL)

        try fileManager.copyItem(at: storeURL, to: backupURL)
        for suffix in sidecarSuffixes {
            let source = sidecarURL(for: storeURL, suffix: suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: sidecarURL(for: backupURL, suffix: suffix))
        }
    }

    /// Restores `storeURL` (and its sidecars) from `backupURL`, so a failed
    /// migration leaves the person on their original, pre-migration data
    /// rather than a partially-written store. Copies (not moves) from the
    /// backup, so the backup itself is still there if this needs to run
    /// again on a subsequent launch (§7 "다음 실행 시 백업 스냅샷에서 재시도").
    private static func restoreBackup(from backupURL: URL, to storeURL: URL) throws {
        let fileManager = FileManager.default
        removeStoreFiles(at: storeURL)

        try fileManager.copyItem(at: backupURL, to: storeURL)
        for suffix in sidecarSuffixes {
            let source = sidecarURL(for: backupURL, suffix: suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: sidecarURL(for: storeURL, suffix: suffix))
        }
    }

    /// Moves the freshly-migrated store at `stagingURL` into `storeURL`'s
    /// place. The main file swap goes through
    /// `FileManager.replaceItemAt(_:withItemAt:)`, which is the standard
    /// atomic file-replace API; the `-wal`/`-shm` sidecars (which that API
    /// doesn't know about) are staged under temporary names *before* the
    /// main swap and only renamed into their final names afterward, so the
    /// main file — the one thing `isConfiguration(withName:
    /// compatibleWithStoreMetadata:)` inspects on the next launch — only
    /// ever flips in a single atomic step.
    private static func swapInMigratedStore(from stagingURL: URL, to storeURL: URL) throws {
        let fileManager = FileManager.default

        var pendingSidecarRenames: [(from: URL, to: URL)] = []
        for suffix in sidecarSuffixes {
            let stagingSidecar = sidecarURL(for: stagingURL, suffix: suffix)
            guard fileManager.fileExists(atPath: stagingSidecar.path) else { continue }
            let incoming = stagingSidecar.appendingPathExtension("incoming")
            try? fileManager.removeItem(at: incoming)
            try fileManager.moveItem(at: stagingSidecar, to: incoming)
            pendingSidecarRenames.append((from: incoming, to: sidecarURL(for: storeURL, suffix: suffix)))
        }

        for suffix in sidecarSuffixes {
            try? fileManager.removeItem(at: sidecarURL(for: storeURL, suffix: suffix))
        }

        _ = try fileManager.replaceItemAt(storeURL, withItemAt: stagingURL)

        for rename in pendingSidecarRenames {
            try? fileManager.removeItem(at: rename.to)
            try fileManager.moveItem(at: rename.from, to: rename.to)
        }
    }

    /// Opens `url` with a throwaway `NSPersistentStoreCoordinator` to
    /// confirm it's actually readable under `model`, then immediately
    /// closes it again — used right after a migration swap, before this
    /// coordinator reports success back to `DatabaseManager`.
    private static func verifyStoreLoads(at url: URL, model: NSManagedObjectModel) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
        try coordinator.remove(store)
    }

    /// Deletes `url` and its `-wal`/`-shm` sidecars, if present. Used to
    /// clear staging/backup files that are no longer needed, and to clear
    /// space for a fresh copy before writing one.
    private static func removeStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: url)
        for suffix in sidecarSuffixes {
            try? fileManager.removeItem(at: sidecarURL(for: url, suffix: suffix))
        }
    }

    /// The `-wal`/`-shm` sidecar path for `baseURL` — SQLite names these by
    /// appending the suffix to the *whole* store filename, e.g.
    /// `local.sqlite-wal`, not by inserting it before the extension.
    private static func sidecarURL(for baseURL: URL, suffix: String) -> URL {
        baseURL.deletingLastPathComponent().appendingPathComponent(baseURL.lastPathComponent + suffix)
    }

    /// Where the pre-migration snapshot of `storeURL` lives while a
    /// migration is in progress (and, if that migration fails, until the
    /// person can recover). Deliberately placed next to the real store in
    /// Application Support — not a `.caches`/temp directory — because the
    /// OS is free to purge caches/temp files under disk pressure at any
    /// time, which would destroy the one copy of the person's pre-migration
    /// data a failed migration needs to fall back to.
    static func backupURL(for storeURL: URL) -> URL {
        renamedStoreURL(storeURL, suffix: "pre-migration-backup")
    }

    /// Where `migrateStoreIfNeeded` writes the migrated store while it's
    /// being built, before swapping it into `storeURL`'s place. Kept next
    /// to the real store so the final swap is a same-volume move/replace.
    static func stagingURL(for storeURL: URL) -> URL {
        renamedStoreURL(storeURL, suffix: "migrating")
    }

    private static func renamedStoreURL(_ storeURL: URL, suffix: String) -> URL {
        let extensionName = storeURL.pathExtension
        let baseName = storeURL.deletingPathExtension().lastPathComponent
        let renamed = "\(baseName).\(suffix)"
        return extensionName.isEmpty
            ? storeURL.deletingLastPathComponent().appendingPathComponent(renamed)
            : storeURL.deletingLastPathComponent().appendingPathComponent(renamed).appendingPathExtension(extensionName)
    }
}
