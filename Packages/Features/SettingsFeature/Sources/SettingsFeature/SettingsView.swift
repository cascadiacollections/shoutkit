import DesignSystem
import FeatureFlags
import Persistence
import Playback
import SwiftUI
import UniformTypeIdentifiers

/// Settings + About, presented as a sheet from the Listen Now toolbar.
public struct SettingsView: View {
    @Environment(\.settingsStore) private var settings
    @Environment(\.libraryStore) private var library
    @Environment(\.playbackController) private var playbackController
    @Environment(\.dismiss) private var dismiss
    private let featureFlags: any FeatureFlagProviding
    @State private var favoritesExportFile: FavoritesExportFile?
    @State private var isExportingFavorites = false
    @State private var isImportingFavorites = false
    @State private var transferAlertMessage: String?
    @State private var isShowingTransferAlert = false

    public init(featureFlags: (any FeatureFlagProviding)? = nil) {
        // Default to the Factory singleton so this view and every other
        // consumer observe the same instance (invalidation is per-instance).
        self.featureFlags = featureFlags ?? sharedFeatureFlags()
    }

    public var body: some View {
        NavigationStack {
            Form {
                privacySection
                if let playbackController, playbackController.supportsEqualizer {
                    equalizerSection
                }
                // Debug and TestFlight builds only: the catalog is all internal
                // placeholder flags, so App Store users have nothing actionable here.
                #if DEBUG || TESTFLIGHT
                featureFlagsSection
                #endif
                favoritesTransferSection
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
            .fileExporter(
                isPresented: $isExportingFavorites,
                document: favoritesExportFile,
                contentType: .json,
                defaultFilename: "shoutkit-favorites"
            ) { result in
                if case .failure(let error) = result {
                    presentTransferAlert(error.localizedDescription)
                }
            }
            .fileImporter(
                isPresented: $isImportingFavorites,
                allowedContentTypes: [.json]
            ) { result in
                handleFavoritesImport(result)
            }
            .alert("Favorites", isPresented: $isShowingTransferAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(transferAlertMessage ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - Sections

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
                ShoutKit has no analytics, no ads, and no accounts.
                """)
            }
        }
    }

    /// Only shown when ``PlaybackController/supportsEqualizer`` is true —
    /// `AVPlayer`-backed engines (the watch companion) have no supported way
    /// to insert a filter into their render chain, so there is nothing here
    /// to offer rather than a control that silently does nothing.
    @ViewBuilder
    private var equalizerSection: some View {
        if let settings, let playbackController {
            Section {
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
            } header: {
                Text("Sound")
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

    private var favoritesTransferSection: some View {
        Section {
            Button("Export Favorites", systemImage: "square.and.arrow.up") {
                startFavoritesExport()
            }
            Button("Import Favorites", systemImage: "square.and.arrow.down") {
                isImportingFavorites = true
            }
        } header: {
            Text("Favorites Backup")
        } footer: {
            Text("""
            Export and import favorites as a plain JSON file. Recents and recently heard tracks are \
            intentionally not included. Import merges by station ID: existing favorites keep their \
            order, and new favorites append at the end.
            """)
        }
        .disabled(library == nil)
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
            Text("Station discovery is powered by Radio-Browser, a free, community-run directory.")
        }
    }

    private func startFavoritesExport() {
        guard let library else {
            presentTransferAlert("Favorites storage is unavailable right now.")
            return
        }
        do {
            favoritesExportFile = try FavoritesExportFile(data: library.exportFavoritesJSONData())
            isExportingFavorites = true
        } catch {
            presentTransferAlert(error.localizedDescription)
        }
    }

    private func handleFavoritesImport(_ result: Result<URL, Error>) {
        guard let library else {
            presentTransferAlert("Favorites storage is unavailable right now.")
            return
        }

        switch result {
        case .success(let url):
            do {
                let data = try readImportedFileData(from: url)
                let importResult = try library.importFavoritesJSONData(data)
                if importResult.addedCount == 0 {
                    presentTransferAlert("No new favorites were imported.")
                } else {
                    presentTransferAlert(
                        "Imported \(importResult.addedCount) favorite\(importResult.addedCount == 1 ? "" : "s")."
                    )
                }
            } catch {
                presentTransferAlert(error.localizedDescription)
            }
        case .failure(let error):
            presentTransferAlert(error.localizedDescription)
        }
    }

    private func readImportedFileData(from url: URL) throws -> Data {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }

    private func presentTransferAlert(_ message: String) {
        transferAlertMessage = message
        isShowingTransferAlert = true
    }
}

#Preview {
    SettingsView()
        .settingsStore(SettingsStore())
}

private struct FavoritesExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
