import Foundation
@testable import NowPlayingActivityKit
import Testing

/// `isNew` is mutating, and `#expect` captures its operands immutably, so each
/// case feeds a sequence through ``passed(_:)`` and asserts on the result.
struct ChangeFilterTests {
    @Test func `the first value is always new`() {
        #expect(passed([0]) == [0])
    }

    @Test func `a repeat of the previous value is not new`() {
        #expect(passed(["KEXP", "KEXP", "KEXP"]) == ["KEXP"])
    }

    @Test func `only consecutive repeats are dropped`() {
        #expect(passed([1, 1, 2, 2, 2, 1, 3, 3]) == [1, 2, 1, 3])
    }

    /// The coordinator filters `URL?` and `NowPlayingMetadata?`, where `nil`
    /// is a real value ("no artwork yet"), not "nothing seen". A first `nil`
    /// must still be delivered, and a later `nil` after a URL is a change.
    @Test func `nil is a value like any other for optional streams`() throws {
        let art = try #require(URL(string: "https://example.com/a.png"))
        #expect(passed([nil, nil, art, art, nil] as [URL?]) == [nil, art, nil])
    }

    private func passed<Value: Equatable>(_ values: [Value]) -> [Value] {
        var filter = ChangeFilter<Value>()
        return values.filter { filter.isNew($0) }
    }
}
