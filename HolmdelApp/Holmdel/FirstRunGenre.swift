import Foundation

/// The six genres offered on the one-time welcome screen.
///
/// The raw value is the allow-list token stored on the device and accepted from
/// a link. ``directoryTag`` is what the directory is queried with: the same
/// capitalisation `RadioBrowserDirectoryClient` applies to tag names, which it
/// then lowercases again on the request. A value that is not one of these cases
/// is not a genre — callers treat `nil` as "show popular stations".
enum FirstRunGenre: String, CaseIterable, Identifiable, Sendable {
    case christmas
    case talk
    case rock
    case news
    case jazz
    case country

    var id: String { rawValue }

    /// Radio-Browser tag, capitalised the same way `Genre` names are.
    var directoryTag: String { rawValue.capitalized }

    /// UserDefaults key for a campaign genre. The seasonal default is not
    /// written here; it is computed when the welcome screen is shown, so
    /// January does not inherit December. Already covered by the privacy
    /// manifest's UserDefaults reason (`CA92.1`); nothing about it leaves
    /// the device.
    static let key = "firstRunGenrePreset"

    /// Campaign genre stored on this device, when the string is one of the chips.
    /// Missing, empty, and unknown values — including ones far longer than any
    /// chip name — are no genre.
    static func saved(in defaults: UserDefaults = .standard) -> FirstRunGenre? {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:))
    }

    /// Christmas from 15 November through 31 December in `calendar`, otherwise
    /// nothing. The window follows the device calendar, so the day turns over
    /// when the listener's day does.
    static func fallback(now: Date = .now, calendar: Calendar = .current) -> FirstRunGenre? {
        let parts = calendar.dateComponents([.month, .day], from: now)
        guard let month = parts.month else { return nil }
        let day = parts.day ?? 0
        if month == 12 || (month == 11 && day >= 15) {
            return .christmas
        }
        return nil
    }

    /// Saved campaign genre, then the seasonal default, then nothing.
    static func preselected(
        now: Date = .now,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard,
    ) -> FirstRunGenre? {
        saved(in: defaults) ?? fallback(now: now, calendar: calendar)
    }
}
