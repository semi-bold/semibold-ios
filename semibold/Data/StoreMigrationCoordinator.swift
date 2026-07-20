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
        /// Swapping the migrated store into place failed (`underlying`),
        /// *and* the attempt to restore `storeURL` from the pre-migration
        /// backup afterward also failed (`rollbackError`). Unlike
        /// `storeSwapFailed`, this does **not** mean the person is safely
        /// back on their pre-migration data — `storeURL` may be missing or
        /// partially written, and this needs surfacing distinctly (rather
        /// than being reported as an ordinary migration failure) so it can
        /// be treated as a data-at-risk situation, not just a failed
        /// upgrade.
        case rollbackFailed(underlying: Error, rollbackError: Error)

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
            case .rollbackFailed(let underlying, let rollbackError):
                return "Store migration failed (\(underlying.localizedDescription)) and restoring the pre-migration "
                    + "backup also failed (\(rollbackError.localizedDescription)) — the existing data may be at risk."
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
    /// `storeURL`. `storeURL` is only ever read from — never written to —
    /// until that final swap, so a failure before the swap (backup, or
    /// migration-to-staging) simply rethrows as `MigrationError`, leaving
    /// `storeURL` untouched; only a failure during or after the swap itself
    /// restores `storeURL` from the backup this method just made. Either
    /// way, the file left behind at `storeURL` is always either the
    /// fully-migrated store or the original pre-migration store — never a
    /// partial/corrupted one.
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
            // written to (migration reads `storeURL` and writes to the
            // separate staging file) — so there is nothing at `storeURL`
            // to roll back, and calling `restoreBackup` here would only
            // expose the still-untouched, still-good `storeURL` to
            // unnecessary risk. Just propagate the failure; the backup
            // stays on disk for the next launch to retry from.
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
            // Unlike the migration-to-staging failure above, `storeURL`
            // may genuinely have been mutated here (the swap started or
            // completed before verification failed), so it needs rolling
            // back from the backup. Do not swallow a rollback failure: if
            // it happens, that's a more severe, distinct situation than an
            // ordinary migration failure (the person's data may now be at
            // risk, not just un-upgraded), so it must surface as its own
            // error rather than being reported as a plain `storeSwapFailed`.
            do {
                try restoreBackup(from: backupURL, to: storeURL)
            } catch let rollbackError {
                throw MigrationError.rollbackFailed(underlying: error, rollbackError: rollbackError)
            }
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
    /// rather than a partially-written store.
    ///
    /// This never deletes anything at `storeURL` until a complete, verified
    /// copy of the backup is already sitting on disk ready to swap in: it
    /// first copies the backup to a disposable restore-staging location
    /// (mirroring how `migrateStoreIfNeeded` stages a migrated store before
    /// touching `storeURL`), and only once that copy has fully succeeded
    /// does it hand off to the same atomic swap `swapInMigratedStore` uses.
    /// If the copy step throws partway (disk full, permissions, interrupted
    /// process), `storeURL` is untouched — worst case this leaves a partial
    /// file at the restore-staging location, which the next attempt clears
    /// before retrying.
    ///
    /// Reads (not moves) from `backupURL`, so the backup itself is still
    /// there if this needs to run again on a subsequent launch (§7 "다음
    /// 실행 시 백업 스냅샷에서 재시도").
    private static func restoreBackup(from backupURL: URL, to storeURL: URL) throws {
        let fileManager = FileManager.default
        let restoreStagingURL = self.restoreStagingURL(for: storeURL)
        removeStoreFiles(at: restoreStagingURL) // clear any leftover from a prior interrupted restore

        try fileManager.copyItem(at: backupURL, to: restoreStagingURL)
        for suffix in sidecarSuffixes {
            let source = sidecarURL(for: backupURL, suffix: suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: sidecarURL(for: restoreStagingURL, suffix: suffix))
        }

        // The staged copy is now a complete duplicate of the backup,
        // confirmed on disk. Only now is it safe to swap it into
        // `storeURL`'s place.
        do {
            try swapInMigratedStore(from: restoreStagingURL, to: storeURL)
        } catch {
            removeStoreFiles(at: restoreStagingURL)
            throw error
        }
    }

    /// Atomically swaps the store at `sourceURL` (a fully-written,
    /// disposable staging copy — either a freshly-migrated store or a
    /// freshly-staged restore-from-backup copy) into `storeURL`'s place.
    ///
    /// The main file swap goes through
    /// `FileManager.replaceItemAt(_:withItemAt:)`, which is the standard
    /// atomic file-replace API. The `-wal`/`-shm` sidecars (which that API
    /// doesn't know about) are staged under temporary names *before* the
    /// main swap, but `storeURL`'s *existing* sidecars are only removed
    /// *after* the main file swap has succeeded — never before. Deleting
    /// them first would leave a window where `storeURL`'s pre-swap main
    /// file is still the one on disk but has lost its WAL journal; for a
    /// WAL-mode SQLite store that was previously terminated abnormally
    /// (e.g. a backgrounded/OOM-killed app — a normal iOS event), some
    /// committed data can live only in that WAL file, so deleting it early
    /// could silently and permanently lose data even if the process is
    /// killed before `replaceItemAt` runs.
    ///
    /// Once `replaceItemAt` has succeeded, `storeURL`'s old sidecars no
    /// longer apply to the new main file (a WAL is only meaningful
    /// alongside the exact file it was journaling for), so they need to be
    /// cleared out and, where a staged replacement exists, replaced with
    /// it. For every suffix that has a staged replacement, that suffix's
    /// old sidecar is removed and its replacement moved into place as one
    /// tight, back-to-back step — never interleaved with work on any other
    /// suffix — so there is no window where that suffix's old sidecar is
    /// gone but its replacement isn't yet at its final path. Only a suffix
    /// with *no* staged replacement (the migrated/restored store simply
    /// had none, e.g. a cleanly-checkpointed source with no `-wal`/`-shm`)
    /// has its stale old sidecar removed on its own — there's nothing
    /// replacing it, so nothing to race against.
    private static func swapInMigratedStore(from sourceURL: URL, to storeURL: URL) throws {
        let fileManager = FileManager.default

        // Stage the source's sidecars under temporary "incoming" names next
        // to the destination, without touching any of the destination's
        // existing files yet.
        var pendingSidecarRenames: [(suffix: String, from: URL, to: URL)] = []
        for suffix in sidecarSuffixes {
            let sourceSidecar = sidecarURL(for: sourceURL, suffix: suffix)
            guard fileManager.fileExists(atPath: sourceSidecar.path) else { continue }
            let incoming = sidecarURL(for: storeURL, suffix: suffix).appendingPathExtension("incoming")
            try? fileManager.removeItem(at: incoming)
            try fileManager.moveItem(at: sourceSidecar, to: incoming)
            pendingSidecarRenames.append((suffix: suffix, from: incoming, to: sidecarURL(for: storeURL, suffix: suffix)))
        }

        // The one atomic step that actually changes what's "the store" at
        // `storeURL` — up to and including this call, `storeURL`'s
        // original main file *and* its original sidecars are both still
        // fully intact together.
        _ = try fileManager.replaceItemAt(storeURL, withItemAt: sourceURL)

        // Only now that the main file has flipped do the old sidecars (which
        // no longer correspond to what's on disk) get cleared. Suffixes with
        // a staged replacement are handled first, one suffix at a time, via
        // `replaceItemAt` — the same atomic-replace primitive used for the
        // main store file above, not a separate remove-then-move pair — so
        // there's no window where a suffix's old sidecar is gone and its
        // replacement isn't yet in place. `replaceItemAt` also handles the
        // case where the suffix has no existing old file at `rename.to`: it
        // simply moves `rename.from` into place, same as a plain move.
        // Only after that do suffixes with no replacement get their stale
        // old sidecar removed on its own — safe because nothing is standing
        // in to take its place.
        let suffixesWithReplacement = Set(pendingSidecarRenames.map(\.suffix))
        for rename in pendingSidecarRenames {
            _ = try fileManager.replaceItemAt(rename.to, withItemAt: rename.from)
        }
        for suffix in sidecarSuffixes where !suffixesWithReplacement.contains(suffix) {
            try? fileManager.removeItem(at: sidecarURL(for: storeURL, suffix: suffix))
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

    /// Where `restoreBackup` stages a full copy of `backupURL` while it's
    /// being written, before swapping it into `storeURL`'s place. Kept next
    /// to the real store for the same same-volume move/replace reason as
    /// `stagingURL(for:)`, and named distinctly from it so a migration
    /// staging file and a restore staging file can never collide if a
    /// migration failure and a rollback ever needed to coexist mid-attempt.
    static func restoreStagingURL(for storeURL: URL) -> URL {
        renamedStoreURL(storeURL, suffix: "restoring")
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
