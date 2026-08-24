import Foundation

/// A minimal favorite-station snapshot the Home Screen quick-play widget renders
/// and deep-links from.
///
/// `deepLinkURLString` is a fully-formed `shoutkit://station?...&autoPlay=1` URL
/// built app-side (where `StationLink` and the `Station` model live), so the
/// widget extension needs no knowledge of the link format or the station model —
/// it only renders the display fields and opens the URL.
public struct QuickPlayStationSnapshot: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let genre: String
    public let deepLinkURLString: String

    public init(id: String, name: String, genre: String, deepLinkURLString: String) {
        self.id = id
        self.name = name
        self.genre = genre
        self.deepLinkURLString = deepLinkURLString
    }
}

/// App Group-backed drop box for the quick-play widget's favorite list. The app
/// writes it whenever favorites change; the widget extension reads it from its
/// own process.
///
/// Mirrors ``LiveActivityArtworkStore``'s container-and-override pattern so unit
/// tests can stage a list in a temp directory without an App Group entitlement.
public enum QuickPlayFavoritesStore {
    /// The quick-play widget's kind identifier. Shared so the app's
    /// `WidgetCenter` reloads target the same widget the extension registers.
    public static let widgetKind = "ShoutKitQuickPlay"

    /// The App Group both the app and the widget extension are entitled to. Must
    /// stay in sync with `Holmdel.entitlements` / `Holmdel.entitlements`.
    public static let appGroupIdentifier = "group.com.cascadiacollections.holmdel"

    private static let directoryName = "QuickPlayFavorites"
    private static let fileName = "favorites.json"

    /// Test-only override for the container directory, so tests can stage a list
    /// in an isolated temp directory without an App Group. Mutated only from test
    /// setup/teardown (never concurrently), hence `nonisolated(unsafe)`.
    nonisolated(unsafe) public static var directoryURLOverride: URL?

    /// Writes the current favorites, replacing any previous list.
    ///
    /// `.noFileProtection`: Home Screen widgets render before the first unlock
    /// after boot, when the default protection class would make the file
    /// unreadable. Station names/genres aren't sensitive, so this is safe and
    /// matches ``LiveActivityArtworkStore``.
    /// - Returns: `true` on success, `false` if the container is unavailable or
    ///   the write fails.
    @discardableResult
    public static func save(_ favorites: [QuickPlayStationSnapshot]) -> Bool {
        guard let directory = directoryURL, let fileURL else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(favorites)
            try data.write(to: fileURL, options: [.atomic, .noFileProtection])
            return true
        } catch {
            return false
        }
    }

    /// Reads the staged favorites, or an empty list if none are staged or the
    /// file can't be read. Read side, used by the widget.
    public static func load() -> [QuickPlayStationSnapshot] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let favorites = try? JSONDecoder().decode([QuickPlayStationSnapshot].self, from: data)
        else { return [] }
        return favorites
    }

    private static var directoryURL: URL? {
        if let directoryURLOverride {
            return directoryURLOverride
        }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static var fileURL: URL? {
        directoryURL?.appendingPathComponent(fileName, isDirectory: false)
    }
}
