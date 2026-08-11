import Testing

@testable import semibold

/// Tests for `OrderKey`'s core guarantee: `orderKey` strings sort
/// correctly under plain lexicographic comparison, including across a
/// digit-count jump, and every `after`/`before`-spaced key stays padded to
/// the same fixed width (`d375924` swift-reviewer follow-up).
struct OrderKeyTests {
    @Test("orderKey strings are always padded to the same fixed width, even after many appends")
    func fixedWidthPadding() {
        var key = OrderKey.between(nil, nil)
        var keys = [key]
        for _ in 0..<20 {
            key = OrderKey.between(key, nil)
            keys.append(key)
        }

        #expect(Set(keys.map(\.count)).count == 1)
    }

    @Test("Repeatedly appending after the last sibling always sorts ascending")
    func monotonicOrderingWhenAppending() {
        var key = OrderKey.between(nil, nil)
        var keys = [key]
        for _ in 0..<20 {
            key = OrderKey.between(key, nil)
            keys.append(key)
        }

        #expect(keys == keys.sorted())
    }

    @Test("Repeatedly inserting before the first sibling always sorts descending")
    func monotonicOrderingWhenPrepending() {
        var key = OrderKey.between(nil, nil)
        var keys = [key]
        for _ in 0..<20 {
            key = OrderKey.between(nil, key)
            keys.append(key)
        }

        #expect(keys == keys.sorted(by: >))
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
