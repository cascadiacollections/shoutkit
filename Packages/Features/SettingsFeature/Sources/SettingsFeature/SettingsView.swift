import DesignSystem
import Persistence
import SwiftUI

/// Settings + About, presented as a sheet from the Listen Now toolbar.
public struct SettingsView: View {
    @Environment(\.settingsStore) private var settings
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                privacySection
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
            } header: {
                Text("Privacy")
            } footer: {
                Text("""
                When on, playing a Radio-Browser station sends its public station ID (nothing \
                about you or your device) so the community directory can rank popularity. \
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
