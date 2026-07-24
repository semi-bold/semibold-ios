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

    @Test("digitMidpoint's exhaustion fallback never sorts past a longer upper bound")
    func exhaustionFallbackStaysBelowLongerUpperBound() {
        // A minimal reproduction of the swift-reviewer's failure: `lower`
        // is shorter than `upper`, and `upper`'s extra trailing digits
        // never leave `digitMidpoint` more than 1 digit of room at any
        // position, so it walks all the way to its growth bound without
        // an early return. The old fallback appended a disambiguating
        // digit to the raw, un-padded `lower` string ("01" + "5" =
        // "015"), which sorts AFTER `upper` here (`upper`'s 3rd digit is
        // "1", less than "015"'s "5") — a silently out-of-order key.
        let lower = "01"
        let upper = "01" + String(repeating: "1", count: 70)

        let newKey = OrderKey.between(lower, upper)

        #expect(newKey > lower, "orderKey \(newKey.prefix(10))... did not sort after lower bound \(lower)")
        #expect(newKey < upper, "orderKey \(newKey.prefix(10))... did not sort before upper bound")
    }

    @Test("Repeatedly inserting new siblings into the same gap never produces a key outside (lower, upper)")
    func repeatedSqueezeAtSamePositionStaysInBounds() {
        // Reproduces the swift-reviewer's failure: inserting several new
        // blocks directly after the same fixed neighbor, each new key
        // becoming the next call's `lower`, used to hit `digitMidpoint`'s
        // digit-growth-exhaustion fallback within only a handful of
        // squeezes — and that fallback appended to the raw, un-padded
        // `lower` string instead of the correctly-accumulated `result`,
        // producing a key that sorted AFTER `upper`.
        let lower = "0100000100"
        let upper = "0100000101"

        var previousKey = lower
        for _ in 0..<20 {
            let newKey = OrderKey.between(previousKey, upper)

            #expect(newKey > lower, "orderKey \(newKey) did not sort after lower bound \(lower)")
            #expect(newKey < upper, "orderKey \(newKey) did not sort before upper bound \(upper)")
            #expect(newKey > previousKey, "orderKey \(newKey) did not sort after the previous insert \(previousKey)")

            previousKey = newKey
        }
    }
}
