import Foundation

/// Builds the string-based fractional index `DocumentItem.orderKey` uses
/// (`tasks/NO-005.md` §2.2) — a string order key that lets a new item be
/// inserted between two existing siblings later without renumbering the
/// whole list.
///
/// `fromLegacySortOrder` is the migration-time conversion: it reproduces a
/// deterministic, lexicographically-sortable key per old
/// `DocumentBlock.sortOrder` value. `between(_:_:)` is the general-purpose
/// counterpart the DocumentItem repository layer's live callers use
/// (`tasks/NO-005.md` §4.3) — `DetailViewModel` (NO-005's ViewModel
/// migration) calls it when creating/reordering a block, instead of
/// renumbering every sibling. Both keep siblings spaced 100 apart
/// internally (matching the spacing `STORAGE_ARCHITECTURE.md` §4's
/// `"000100"`/`"000200"` worked example uses, so a later insert between two
/// items still has room) — the emitted string is wider than that example
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

    /// The spacing `fromLegacySortOrder` leaves between two consecutive
    /// migrated siblings — reused by `after`/`before` below so a freshly
    /// created item next to migrated ones keeps the same headroom for
    /// further inserts.
    private static let spacing: Int64 = 100

    /// Builds a fresh `orderKey` for a new sibling, given its immediate
    /// neighbors' current `orderKey`s (`nil` meaning "no sibling on that
    /// side" — the very start/end of the list, or an otherwise-empty
    /// parent). This is the live, general-purpose counterpart to
    /// `fromLegacySortOrder` this file's original scope note deferred to
    /// "the DocumentItem repository layer" (`tasks/NO-005.md` §2.2) —
    /// `DetailViewModel` (`markdown-phase4`'s NO-005 ViewModel migration)
    /// is that caller, using this instead of renumbering every sibling on
    /// every block create/reorder.
    ///
    /// Only ever touches the ONE item being inserted/moved — every other
    /// sibling's `orderKey` stays exactly as it was, which is the whole
    /// point of a fractional/string order key over the old integer
    /// `sortOrder` (`tasks/NO-005.md` §2.2's motivation).
    static func between(_ lower: String?, _ upper: String?) -> String {
        switch (lower, upper) {
        case (nil, nil):
            return fromLegacySortOrder(0)
        case (nil, let upper?):
            return before(upper)
        case (let lower?, nil):
            return after(lower)
        case (let lower?, let upper?):
            return digitMidpoint(lower, upper)
        }
    }

    /// A key spaced `spacing` after `previous`, for appending a sibling
    /// with nothing after it (e.g. a new block added at the end of the
    /// document). Falls back to `digitMidpoint` (open-ended above) if
    /// `previous` isn't in the plain fixed-width numeric shape this
    /// spacing arithmetic expects — e.g. it was itself produced by an
    /// earlier `digitMidpoint` digit-growth fallback.
    private static func after(_ previous: String) -> String {
        guard previous.count == paddedWidth, let value = Int64(previous) else {
            return digitMidpoint(previous, nil)
        }
        let next = min(value + spacing, maxSpaced)
        guard next > value else { return digitMidpoint(previous, nil) }
        let digits = String(next)
        return String(repeating: "0", count: paddedWidth - digits.count) + digits
    }

    /// A key spaced `spacing` before `next`, for inserting a sibling with
    /// nothing before it (e.g. moving a block to the very top). Mirrors
    /// `after` above, floored at 0.
    private static func before(_ next: String) -> String {
        guard next.count == paddedWidth, let value = Int64(next), value > 0 else {
            return digitMidpoint(nil, next)
        }
        let previous = max(value - spacing, 0)
        guard previous < value else { return digitMidpoint(nil, next) }
        let digits = String(previous)
        return String(repeating: "0", count: paddedWidth - digits.count) + digits
    }

    /// Finds a decimal digit string strictly between `lower` and `upper`
    /// (each `nil` meaning an open bound — 0 below, or "no ceiling" above)
    /// by walking digit-by-digit until there's room for a value strictly
    /// between the two at that position, growing the result by one more
    /// digit at a time only when it has to. A missing digit on either
    /// side (one key shorter than the other, or a `nil` bound) is treated
    /// as `0`, EXCEPT a `nil` `upper` bound, which is treated as one past
    /// `9` at every position so there's always room above any finite
    /// `lower` value.
    ///
    /// Every key this method returns keeps `lower`'s existing digits as
    /// its own prefix wherever it had to grow past the shorter of the two
    /// inputs — since a longer string that shares a shorter one's digits
    /// as a prefix always sorts after it lexicographically (`"12" <
    /// "120"` the same way `"12" < "125"` does), this preserves the
    /// "plain string comparison agrees with fraction order" guarantee
    /// `fromLegacySortOrder`'s doc comment establishes, even once keys
    /// stop sharing one fixed width.
    ///
    /// Bounded to `maxDigitGrowth` digits of growth PAST the longer of
    /// `lower`/`upper`'s own length, so a caller can never hit an infinite
    /// loop even if `lower`/`upper` were passed in an already-invalid order
    /// (`lower >= upper`) — falls back to `lower` (or `""`) with a single
    /// disambiguating digit appended in that case.
    ///
    /// The bound is relative to `lower`/`upper`'s length — not a fixed
    /// absolute digit count — so that repeatedly squeezing new siblings
    /// into the same gap (each new key becoming the next call's `lower`,
    /// itself already `maxDigitGrowth` digits longer than before from the
    /// previous squeeze's own exhaustion fallback) keeps getting a full
    /// `maxDigitGrowth` digits of headroom on every call, rather than
    /// exhausting on the very first walked digit once `lower` alone is
    /// already longer than a fixed absolute bound would allow. Without
    /// this, a second squeeze into an already-exhausted gap would produce
    /// the exact same fallback key as the first (since the walk would
    /// never reach the newly-grown digits at all) — a silent duplicate
    /// `orderKey`, not merely an out-of-order one.
    private static func digitMidpoint(_ lower: String?, _ upper: String?) -> String {
        let lowerDigits = Array(lower ?? "")
        let upperDigits = upper.map(Array.init)
        var result = ""
        var index = 0
        let maxDigitGrowth = 64
        let growthLimit = max(lowerDigits.count, upperDigits?.count ?? 0) + maxDigitGrowth

        while index < growthLimit {
            let lowDigit = index < lowerDigits.count ? (lowerDigits[index].wholeNumberValue ?? 0) : 0
            let highDigit: Int
            if let upperDigits {
                highDigit = index < upperDigits.count ? (upperDigits[index].wholeNumberValue ?? 0) : 0
            } else {
                // No upper bound — always leave room above `lowDigit`.
                highDigit = 10
            }

            if highDigit - lowDigit >= 2 {
                result.append(Character(String(lowDigit + (highDigit - lowDigit) / 2)))
                return result
            }
            result.append(Character(String(lowDigit)))
            index += 1
        }

        // Exhausted `growthLimit` digits of growth without finding room.
        // `result` mirrors `lower`'s own digits (zero-padded consistently)
        // at every position walked so far, so appending to it — not to the
        // raw, un-padded `lower` string — is what keeps this key sorting
        // strictly after `lower`. (Appending to raw `lower` broke that
        // guarantee whenever `result`'s padding had already diverged from
        // `lower`'s literal digits, producing a key that could sort past
        // `upper`.)
        return result + "5"
    }
}
