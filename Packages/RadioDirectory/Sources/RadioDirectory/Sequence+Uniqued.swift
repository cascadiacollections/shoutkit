extension Sequence {
    /// The elements in order, keeping only the first with each `key`.
    ///
    /// Stands in for swift-algorithms' `uniqued(on:)`, the only API this
    /// package used from it. Dropping the dependency took its linked code out
    /// of the app binary (DECISIONS.md, 2026-11-07).
    func uniqued<Key: Hashable>(on key: (Element) throws -> Key) rethrows -> [Element] {
        var seen = Set<Key>()
        var result: [Element] = []
        for element in self where try seen.insert(key(element)).inserted {
            result.append(element)
        }
        return result
    }
}
