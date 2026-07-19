import Testing

@testable import semibold

/// Tests for `OrderKey.fromLegacySortOrder`'s core guarantee: distinct
/// `sortOrder` values always produce distinct, correctly-ordered
/// `orderKey` strings under plain lexicographic comparison — including
/// across a magnitude jump (e.g. 4-digit vs. 5-digit `spaced` values) and
/// for negative `sortOrder` (`d375924` swift-reviewer follow-up).
struct OrderKeyTests {
    @Test("A larger sortOrder always produces a lexicographically larger orderKey, even across a digit-count jump")
    func ordersAcrossDigitJump() {
        // sortOrder 9998 vs. 9999 used to straddle a 6-digit/7-digit
        // boundary ("999900" vs. "1000000"), which broke lexicographic
        // comparison. Fixed-width padding must keep both the same length.
        let lower = OrderKey.fromLegacySortOrder(9998)
        let higher = OrderKey.fromLegacySortOrder(9999)

        #expect(lower.count == higher.count)
        #expect(lower < higher)
    }

    @Test("Distinct negative sortOrder values produce distinct, correctly-ordered orderKeys")
    func distinctNegativeSortOrders() {
        let keyForNegFive = OrderKey.fromLegacySortOrder(-5)
        let keyForNegOne = OrderKey.fromLegacySortOrder(-1)
        let keyForZero = OrderKey.fromLegacySortOrder(0)

        #expect(keyForNegFive != keyForNegOne)
        #expect(keyForNegOne != keyForZero)
        #expect(keyForNegFive < keyForNegOne)
        #expect(keyForNegOne < keyForZero)
    }

    @Test("orderKey strings are always padded to the same fixed width")
    func fixedWidthPadding() {
        let values: [Int64] = [-1_000, -1, 0, 1, 42, 9998, 9999, 100_000]
        let keys = values.map(OrderKey.fromLegacySortOrder)
        let widths = Set(keys.map(\.count))

        #expect(widths.count == 1)
    }

    @Test("Ascending sortOrder values always sort ascending as orderKey strings")
    func monotonicOrdering() {
        let values: [Int64] = [-100, -50, -1, 0, 1, 50, 100, 5_000, 9_998, 9_999, 50_000]
        let keys = values.map(OrderKey.fromLegacySortOrder)

        #expect(keys == keys.sorted())
    }
}
