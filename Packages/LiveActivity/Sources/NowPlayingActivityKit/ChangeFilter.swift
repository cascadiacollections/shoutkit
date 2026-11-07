/// Drops consecutive repeats from a stream of values: the first value is
/// always new, and after that only a value unequal to the last one is.
///
/// Stands in for swift-async-algorithms' `removeDuplicates()`, the only API
/// this package used from it; dropping the dependency took ~1 MB of linked code
/// out of the app binary (DECISIONS.md, 2026-11-07).
struct ChangeFilter<Value: Equatable> {
    private var last: Value?
    private var hasLast = false

    /// Whether `value` differs from the previous one, recording it either way.
    mutating func isNew(_ value: Value) -> Bool {
        defer {
            last = value
            hasLast = true
        }
        return hasLast == false || last != value
    }
}
