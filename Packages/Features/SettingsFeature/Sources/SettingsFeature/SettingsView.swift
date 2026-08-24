import DesignSystem
import FeatureFlags
import Persistence
import Playback
import SwiftUI

/// Settings + About, presented as a sheet from the Listen Now toolbar.
public struct SettingsView: View {
    @Environment(\.settingsStore) private var settings
    @Environment(\.playbackController) private var playbackController
    @Environment(\.dismiss) private var dismiss
    private let featureFlags: any FeatureFlagProviding

    public init(featureFlags: (any FeatureFlagProviding)? = nil) {
        // Default to the Factory singleton so this view and every other
        // consumer observe the same instance (invalidation is per-instance).
        self.featureFlags = featureFlags ?? sharedFeatureFlags()
    }

    public var body: some View {
        NavigationStack {
            Form {
                playbackSection
                privacySection
                if let playbackController,
                   playbackController.supportsEqualizer || playbackController.supportsSpatialAudio {
                    soundSection
                }
                // Debug and TestFlight builds only: the catalog is all internal
                // placeholder flags, so App Store users have nothing actionable here.
                #if DEBUG || TESTFLIGHT
                featureFlagsSection
                #endif
                supportSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    /// The one playback behaviour a listener has to be able to choose, because
    /// either answer is wrong for half the stations: a continuous live stream
    /// never ends, while a station that broadcasts a fixed-length programme does.
    /// Off by default — a finished broadcast stops, the way every other player
    /// treats it.
    @ViewBuilder
    private var playbackSection: some View {
        if let settings {
            Section {
                Toggle(
                    "Loop Finished Broadcasts",
                    isOn: Binding(
                        get: { settings.isStreamLoopingEnabled },
                        set: { settings.isStreamLoopingEnabled = $0 }
                    )
                )
            } header: {
                Text("Playback")
            } footer: {
                Text("""
                Most stations stream continuously and never end, so this changes nothing for \
                them. A station that broadcasts a fixed-length programme — an hourly newscast, \
                say — stops when it reaches the end; turn this on to have it start over instead.
                """)
            }
        }
    }

    @ViewBuilder
    private var privacySection: some View {
        if let settings {
            let isGeoStationsEnabled = featureFlags.isEnabled(FeatureCatalog.geoStations)

            Section {
                Toggle(
                    "Report Plays to Radio-Browser",
                    isOn: Binding(
                        get: { settings.isPlayReportingEnabled },
                        set: { settings.isPlayReportingEnabled = $0 }
                    )
                )
                Toggle(
                    "Fetch Album Artwork",
                    isOn: Binding(
                        get: { settings.isAlbumArtEnabled },
                        set: { settings.isAlbumArtEnabled = $0 }
                    )
                )
                Toggle(
                    "Share diagnostics",
                    isOn: Binding(
                        get: { settings.isDiagnosticsSharingEnabled },
                        set: { settings.isDiagnosticsSharingEnabled = $0 }
                    )
                )
                if isGeoStationsEnabled {
                    Toggle(
                        "Use Precise Location for Geo Stations",
                        isOn: Binding(
                            get: { settings.isPreciseGeoStationLocationEnabled },
                            set: { settings.isPreciseGeoStationLocationEnabled = $0 }
                        )
                    )
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("""
                When on, playing a Radio-Browser station sends its public station ID (nothing \
                about you or your device) so the community directory can rank popularity. \
                Album artwork lookups send the current track's artist and title to Apple's \
                iTunes Search API; turn this off to always show station artwork instead. \
                Share diagnostics keeps Apple MetricKit crash/hang/energy/disk payloads local \
                on-device for troubleshooting. They are never sent automatically; export/share \
                would only happen if you explicitly choose to do that for debugging later. The \
                geo-stations feature defaults to your device locale region with no permission \
                prompt; the optional precise-location toggle asks Apple for location permission \
                only after you turn it on, and falls back to that locale region if permission \
                is denied. \
                Holmdel has no analytics, no ads, and no accounts.
                """)
            }
        }
    }

    /// Equalizer picker and/or spatial audio toggle, each shown only when the
    /// active engine reports it can back it — `AVPlayer`-backed engines (the
    /// watch companion) have no supported way to insert either into their
    /// render chain, so there is nothing here to offer rather than a control
    /// that silently does nothing.
    @ViewBuilder
    private var soundSection: some View {
        if let settings, let playbackController {
            Section {
                if playbackController.supportsEqualizer {
                    Picker(
                        "Equalizer",
                        selection: Binding(
                            get: { EqualizerPreset(rawValue: settings.equalizerPresetRawValue) ?? .normal },
                            set: { preset in
                                settings.equalizerPresetRawValue = preset.rawValue
                                playbackController.setEqualizerPreset(preset)
                            }
                        )
                    ) {
                        ForEach(EqualizerPreset.allCases, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                }
                if playbackController.supportsSpatialAudio {
                    Toggle(
                        "Spatial Audio",
                        isOn: Binding(
                            get: { settings.isSpatialAudioEnabled },
                            set: { isEnabled in
                                settings.isSpatialAudioEnabled = isEnabled
                                playbackController.setSpatialAudioEnabled(isEnabled)
                            }
                        )
                    )
                }
            } header: {
                Text("Sound")
            } footer: {
                if playbackController.supportsSpatialAudio {
                    Text("""
                    Spatial Audio renders the stream through a head-tracked virtual sound stage on \
                    AirPods and other supported headphones. It's a stereo effect Holmdel applies to \
                    every station, not Dolby Atmos content from the broadcaster — radio streams carry \
                    no object-based audio to spatialize.
                    """)
                }
            }
        }
    }

    private var supportSection: some View {
        Section {
            Link(destination: ProjectLinks.issues) {
                Label("Report an Issue", systemImage: "ladybug")
            }
            Link(destination: ProjectLinks.sponsors) {
                Label("Support Holmdel", systemImage: "heart")
            }
        } header: {
            Text("Feedback & Support")
        } footer: {
            Text("""
            Holmdel is free software — everything works whether or not you donate. \
            On beta builds you can also send feedback by taking a screenshot in TestFlight.
            """)
        }
    }

    #if DEBUG || TESTFLIGHT
    private var featureFlagsSection: some View {
        Section {
            NavigationLink {
                FeatureFlagsView(featureFlags: featureFlags)
            } label: {
                Label("Feature Flags", systemImage: "switch.2")
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Feature flags are stored locally on this device and apply immediately.")
        }
    }
    #endif

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: AppInfo.versionString)
                .textSelection(.enabled)
            Link(destination: ProjectLinks.repository) {
                Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            NavigationLink {
                LicensesView()
            } label: {
                Label("Licenses", systemImage: "doc.text")
            }
            Link(destination: ProjectLinks.radioBrowser) {
                Label("Radio-Browser", systemImage: "dot.radiowaves.left.and.right")
            }
        } header: {
            Text("About")
        } footer: {
            Text("""
            Holmdel is named for the Bell Labs site in Holmdel, New Jersey, where in 1964 Arno \
            Penzias and Robert Wilson used the Holmdel Horn Antenna to detect the cosmic \
            microwave background — proof of the Big Bang, and one of the most consequential \
            radio signals ever received. Station discovery here is powered by Radio-Browser, a \
            free, community-run directory.
            """)
        }
    }
}

#Preview {
    SettingsView()
        .settingsStore(SettingsStore())
}
