import Foundation
import Observation

/// App-wide user preferences, UserDefaults-backed. Kept in Persistence (not a
/// feature package) because the composition root consults it — e.g. the
/// play-reporting hook checks ``isPlayReportingEnabled`` before calling out.
@MainActor
@Observable
public final class SettingsStore {
    private enum Keys {
        static let playReporting = DefaultsKey<Bool>.plist("settings.playReportingEnabled", default: true)
        static let albumArt = DefaultsKey<Bool>.plist("settings.albumArtEnabled", default: true)
        static let preciseGeoStationLocation = DefaultsKey<Bool>.plist(
            "settings.preciseGeoStationLocationEnabled",
            default: false
        )
    }

    /// Whether plays are reported to Radio-Browser (station UUID only, per that
    /// project's etiquette). Defaults to on — the report is anonymous and keeps
    /// the community directory's popularity ranking healthy — but the README
    /// privacy story promises this is the user's call, hence the toggle.
    public var isPlayReportingEnabled: Bool {
        didSet { defaults.set(isPlayReportingEnabled, for: Keys.playReporting) }
    }

    /// Whether the app fetches album artwork from the iTunes Search API when
    /// track metadata is available and uses it in the Now Playing UI. Defaults
    /// to on. Opt-out is provided for users who prefer station artwork only or
    /// who want to avoid the supplemental iTunes network request.
    public var isAlbumArtEnabled: Bool {
        didSet { defaults.set(isAlbumArtEnabled, for: Keys.albumArt) }
    }

    /// Whether ShoutKit may request Core Location permission to reverse-geocode
    /// the current country for geo-station filtering. Defaults to off so the
    /// locale-based country filter stays permissionless unless the user opts in.
    /// This only has an effect while the geo-stations feature flag is enabled.
    public var isPreciseGeoStationLocationEnabled: Bool {
        didSet { defaults.set(isPreciseGeoStationLocationEnabled, for: Keys.preciseGeoStationLocation) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPlayReportingEnabled = defaults.value(for: Keys.playReporting)
        isAlbumArtEnabled = defaults.value(for: Keys.albumArt)
        isPreciseGeoStationLocationEnabled = defaults.value(for: Keys.preciseGeoStationLocation)
    }
}
