import Foundation

/// Converts a legacy integer `DocumentBlock.sortOrder` into the
/// string-based fractional index `DocumentItem.orderKey` uses
/// (`tasks/NO-005.md` §2.2) — a string order key that lets a new item be
/// inserted between two existing siblings later without renumbering the
/// whole list.
///
/// This is only the migration-time conversion: it reproduces a
/// deterministic, lexicographically-sortable key per old `sortOrder`
/// value, not a general-purpose fractional-index generator (that belongs
/// to the DocumentItem repository layer, `tasks/NO-005.md` §4.3, out of
/// this brief's scope). Siblings are spaced 100 apart internally (matching
/// the spacing `STORAGE_ARCHITECTURE.md` §4's `"000100"`/`"000200"`
/// worked example uses, so a later insert between two migrated items
/// still has room) — the emitted string is wider than that example
/// because of the fixed padding/offset below, e.g. `sortOrder = 0` →
/// `"0100000000"`, not `"000100"`.
enum OrderKey {
    /// The zero-padded width every migrated `orderKey` uses. Every key is
    /// padded to exactly this width — never left shorter, never allowed
    /// to grow longer — so lexicographic string comparison always agrees
    /// with numeric order, at any magnitude (`fromLegacySortOrder`'s
    /// guarantee below).
    ///
    /// 10 digits covers `sortOrder` up to 99_999_998 (see `offset`/
    /// `maxSpaced` below) — far beyond any realistic sibling-group size —
    /// with room to spare before the fixed width would need to grow.
    private static let paddedWidth = 10

    /// `sortOrder` values are shifted up by this much before spacing so
    /// that negative inputs (shouldn't occur in practice, but must still
    /// round-trip to distinct keys rather than colliding) map to distinct,
    /// correctly-ordered non-negative keys. Comfortably covers any
    /// realistic negative `sortOrder`.
    ///
    /// Caveat: `sortOrder` values at or beyond ±`offset`/±`maxSpaced`
    /// magnitude (far outside any real `DocumentBlock.sortOrder`, which is
    /// a small per-parent list position) still clamp and can collide at
    /// those extremes — this conversion is only exact within the
    /// realistic legacy sortOrder range, not for arbitrary `Int64` input.
    private static let offset: Int64 = 1_000_000

    /// The largest `spaced` value `paddedWidth` digits can represent
    /// (`10^paddedWidth - 1`). `sortOrder` is clamped so the padded
    /// decimal string never grows past `paddedWidth` and silently breaks
    /// the lexicographic-order guarantee.
    private static let maxSpaced: Int64 = {
        var value: Int64 = 1
        for _ in 0..<paddedWidth { value *= 10 }
        return value - 1
    }()

    /// Builds the `orderKey` for the item that was at position
    /// `sortOrder` (0-based, per-parent — `DocumentBlockRepository`
    /// already scopes `sortOrder` to siblings under the same parent, so
    /// this needs no `parentItemId` input of its own).
    ///
    /// Guarantee: for any two `sortOrder` values within the supported
    /// range, `a < b` implies `fromLegacySortOrder(a) <
    /// fromLegacySortOrder(b)` under plain string (lexicographic)
    /// comparison — every key is padded to the same fixed
    /// `paddedWidth`, so no magnitude jump (e.g. crossing from 6 digits
    /// to 7) can ever invert the order the way an unpadded/overflowing
    /// key would.
    static func fromLegacySortOrder(_ sortOrder: Int64) -> String {
        let shifted = max(0, sortOrder + offset)
        let spaced = min(shifted, maxSpaced / 100) * 100
        let digits = String(spaced)
        return String(repeating: "0", count: paddedWidth - digits.count) + digits
    }
}
