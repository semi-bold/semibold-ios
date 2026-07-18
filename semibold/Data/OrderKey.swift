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
/// this brief's scope). Siblings are spaced 100 apart — `"000100"`,
/// `"000200"`, … the shape `STORAGE_ARCHITECTURE.md` §4's worked example
/// uses — so a later insert between two migrated items still has room.
enum OrderKey {
    /// The zero-padded width every migrated `orderKey` uses, matching
    /// `STORAGE_ARCHITECTURE.md` §4's `"000100"` example. Comfortably
    /// covers realistic sibling-group sizes (up to ~9,999 items before a
    /// key needs to grow past this width); see `fromLegacySortOrder` for
    /// what happens beyond that.
    private static let paddedWidth = 6

    /// Builds the `orderKey` for the item that was at position
    /// `sortOrder` (0-based, per-parent — `DocumentBlockRepository`
    /// already scopes `sortOrder` to siblings under the same parent, so
    /// this needs no `parentItemId` input of its own).
    ///
    /// Negative `sortOrder` (shouldn't occur in practice) is clamped to
    /// 0. Beyond `paddedWidth` digits the key simply grows longer rather
    /// than truncating — since every migrated key grows in the same
    /// left-to-right digit order, lexicographic comparison still matches
    /// numeric order for realistic sibling-group sizes.
    static func fromLegacySortOrder(_ sortOrder: Int64) -> String {
        let spaced = max(0, sortOrder + 1) * 100
        let digits = String(spaced)
        guard digits.count < paddedWidth else { return digits }
        return String(repeating: "0", count: paddedWidth - digits.count) + digits
    }
}
