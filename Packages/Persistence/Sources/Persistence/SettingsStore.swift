import Foundation
import Observation

/// App-wide user preferences, UserDefaults-backed. Kept in Persistence (not a
/// feature package) because the composition root consults it — e.g. the
/// play-reporting hook checks ``isPlayReportingEnabled`` before calling out.
@MainActor
@Observable
public final class SettingsStore {
    private enum Keys {
        static let playReporting = "settings.playReportingEnabled"
        static let albumArt = "settings.albumArtEnabled"
    }

    /// Whether plays are reported to Radio-Browser (station UUID only, per that
    /// project's etiquette). Defaults to on — the report is anonymous and keeps
    /// the community directory's popularity ranking healthy — but the README
    /// privacy story promises this is the user's call, hence the toggle.
    public var isPlayReportingEnabled: Bool {
        didSet { defaults.set(isPlayReportingEnabled, forKey: Keys.playReporting) }
    }

    /// Whether the app fetches album artwork from the iTunes Search API when
    /// track metadata is available and uses it in the Now Playing UI. Defaults
    /// to on. Opt-out is provided for users who prefer station artwork only or
    /// who want to avoid the supplemental iTunes network request.
    public var isAlbumArtEnabled: Bool {
        didSet { defaults.set(isAlbumArtEnabled, forKey: Keys.albumArt) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPlayReportingEnabled = defaults.object(forKey: Keys.playReporting) as? Bool ?? true
        isAlbumArtEnabled = defaults.object(forKey: Keys.albumArt) as? Bool ?? true
    }
}
