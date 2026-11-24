import Foundation
@testable import Holmdel
import Testing

struct FirstRunGenreTests {
    @Test func `chips use the directory's capitalised tag names in row order`() {
        #expect(FirstRunGenre.allCases.map(\.directoryTag) == [
            "Christmas", "Talk", "Rock", "News", "Jazz", "Country",
        ])
    }

    @Test(arguments: [
        FallbackSample(month: 11, day: 14, expected: nil),
        FallbackSample(month: 11, day: 15, expected: .christmas),
        FallbackSample(month: 12, day: 31, expected: .christmas),
        FallbackSample(month: 1, day: 1, expected: nil),
    ])
    func `seasonal default follows the calendar day`(_ sample: FallbackSample) throws {
        let calendar = try utcCalendar()
        let now = try date(month: sample.month, day: sample.day, calendar: calendar)

        #expect(FirstRunGenre.fallback(now: now, calendar: calendar) == sample.expected)
    }

    @Test func `saved genre wins over the season`() throws {
        let defaults = try makeDefaults()
        defaults.set(FirstRunGenre.rock.rawValue, forKey: FirstRunGenre.key)
        let calendar = try utcCalendar()
        let christmasEve = try date(month: 12, day: 24, calendar: calendar)

        let picked = FirstRunGenre.preselected(now: christmasEve, calendar: calendar, defaults: defaults)

        #expect(picked == .rock)
    }

    @Test func `seasonal default is computed and not stored`() throws {
        let defaults = try makeDefaults()
        let calendar = try utcCalendar()
        let christmasEve = try date(month: 12, day: 24, calendar: calendar)

        let picked = FirstRunGenre.preselected(now: christmasEve, calendar: calendar, defaults: defaults)

        #expect(picked == .christmas)
        #expect(defaults.string(forKey: FirstRunGenre.key) == nil)
    }

    @Test func `an unknown or oversized stored value is ignored`() throws {
        let defaults = try makeDefaults()
        defaults.set(String(repeating: "x", count: 10_000), forKey: FirstRunGenre.key)
        let calendar = try utcCalendar()
        let newYear = try date(month: 1, day: 1, calendar: calendar)
        let christmasEve = try date(month: 12, day: 24, calendar: calendar)

        #expect(FirstRunGenre.saved(in: defaults) == nil)
        #expect(FirstRunGenre.preselected(now: newYear, calendar: calendar, defaults: defaults) == nil)
        #expect(FirstRunGenre.preselected(now: christmasEve, calendar: calendar, defaults: defaults) == .christmas)
    }

    @Test func `with nothing saved outside the season nothing is selected`() throws {
        let defaults = try makeDefaults()
        let calendar = try utcCalendar()
        let summer = try date(month: 7, day: 4, calendar: calendar)

        #expect(FirstRunGenre.preselected(now: summer, calendar: calendar, defaults: defaults) == nil)
    }

    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return calendar
    }

    private func date(month: Int, day: Int, year: Int = 2026, calendar: Calendar) throws -> Date {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        return try #require(parts.date)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "FirstRunGenreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

struct FallbackSample: Sendable {
    let month: Int
    let day: Int
    let expected: FirstRunGenre?
}
