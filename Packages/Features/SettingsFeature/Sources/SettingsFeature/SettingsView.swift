import DesignSystem
import FeatureFlags
import Persistence
import SwiftUI

/// Settings + About, presented as a sheet from the Listen Now toolbar.
public struct SettingsView: View {
    @Environment(\.settingsStore) private var settings
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
                privacySection
                // Debug builds only: the catalog is all internal placeholder
                // flags, so end users have nothing actionable here.
                #if DEBUG
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

    @ViewBuilder
    private var privacySection: some View {
        if let settings {
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
            } header: {
                Text("Privacy")
            } footer: {
                Text("""
                When on, playing a Radio-Browser station sends its public station ID (nothing \
                about you or your device) so the community directory can rank popularity. \
                Album artwork lookups send the current track's artist and title to Apple's \
                iTunes Search API; turn this off to always show station artwork instead. \
                ShoutKit has no analytics, no ads, and no accounts.
                """)
            }
        }
    }

    private var supportSection: some View {
        Section {
            Link(destination: ProjectLinks.issues) {
                Label("Report an Issue", systemImage: "ladybug")
            }
            Link(destination: ProjectLinks.sponsors) {
                Label("Support ShoutKit", systemImage: "heart")
            }
        } header: {
            Text("Feedback & Support")
        } footer: {
            Text("""
            ShoutKit is free software — everything works whether or not you donate. \
            On beta builds you can also send feedback by taking a screenshot in TestFlight.
            """)
        }
    }

    #if DEBUG
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
            Text("Station discovery is powered by Radio-Browser, a free, community-run directory.")
        }
    }
}

#Preview {
    SettingsView()
        .settingsStore(SettingsStore())
}
