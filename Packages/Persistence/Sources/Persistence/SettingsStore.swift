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
        static let diagnosticsSharing = DefaultsKey<Bool>.plist("settings.diagnosticsSharingEnabled", default: false)
        static let preciseGeoStationLocation = DefaultsKey<Bool>.plist(
            "settings.preciseGeoStationLocationEnabled",
            default: false
        )
        static let equalizerPreset = DefaultsKey<Int>.plist("settings.equalizerPresetRawValue", default: 0)
        static let streamLooping = DefaultsKey<Bool>.plist("settings.streamLoopingEnabled", default: false)
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

    /// Whether anonymous diagnostics payloads from Apple's MetricKit may be
    /// collected locally on-device for later export/debugging. Defaults to off.
    public var isDiagnosticsSharingEnabled: Bool {
        didSet { defaults.set(isDiagnosticsSharingEnabled, for: Keys.diagnosticsSharing) }
    }

    /// Whether ShoutKit may request Core Location permission to reverse-geocode
    /// the current country for geo-station filtering. Defaults to off so the
    /// locale-based country filter stays permissionless unless the user opts in.
    /// This only has an effect while the geo-stations feature flag is enabled.
    public var isPreciseGeoStationLocationEnabled: Bool {
        didSet { defaults.set(isPreciseGeoStationLocationEnabled, for: Keys.preciseGeoStationLocation) }
    }

    /// The last equalizer preset applied, stored as `EqualizerPreset.rawValue`
    /// (an `Int`) rather than the `Playback` package's enum type itself —
    /// `Persistence` doesn't depend on `Playback`, and this keeps it that way.
    /// Defaults to `0`, `EqualizerPreset.normal`'s raw value (flat, no EQ).
    public var equalizerPresetRawValue: Int {
        didSet { defaults.set(equalizerPresetRawValue, for: Keys.equalizerPreset) }
    }

    /// Whether a station that broadcasts a fixed-length programme — NPR's hourly
    /// newscast is the case this exists for — starts over when it finishes
    /// instead of stopping. Defaults to off: playing once is what a broadcast
    /// with an end means, and repeating it is a choice the listener makes. Has no
    /// effect on continuous live streams, which never end on their own.
    public var isStreamLoopingEnabled: Bool {
        didSet { defaults.set(isStreamLoopingEnabled, for: Keys.streamLooping) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPlayReportingEnabled = defaults.value(for: Keys.playReporting)
        isAlbumArtEnabled = defaults.value(for: Keys.albumArt)
        isDiagnosticsSharingEnabled = defaults.value(for: Keys.diagnosticsSharing)
        isPreciseGeoStationLocationEnabled = defaults.value(for: Keys.preciseGeoStationLocation)
        equalizerPresetRawValue = defaults.value(for: Keys.equalizerPreset)
        isStreamLoopingEnabled = defaults.value(for: Keys.streamLooping)
    }
}
