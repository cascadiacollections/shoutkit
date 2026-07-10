import Foundation
import Testing

@testable import Persistence

struct DefaultsKeyTests {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "DefaultsKeyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func plistReturnsDefaultWhenUnset() throws {
        let defaults = try makeDefaults()
        let key = DefaultsKey<Bool>.plist("test.bool.key", default: true)

        #expect(defaults.value(for: key) == true)
    }

    @Test func plistRoundTripsWrittenValue() throws {
        let defaults = try makeDefaults()
        let key = DefaultsKey<Bool>.plist("test.bool.key", default: true)

        defaults.set(false, for: key)

        #expect(defaults.value(for: key) == false)
    }

    @Test func codableSetRoundTripsAndDefaultsWhenUnset() throws {
        let defaults = try makeDefaults()
        let key = DefaultsKey<Set<String>>.codable("test.set.key", default: ["fallback"])

        #expect(defaults.value(for: key) == ["fallback"])

        defaults.set(["kexp", "wbez"], for: key)

        #expect(defaults.value(for: key) == ["kexp", "wbez"])
    }
}
