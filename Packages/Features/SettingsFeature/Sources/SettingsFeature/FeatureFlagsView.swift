#if DEBUG || TESTFLIGHT
import FeatureFlags
import Persistence
import SwiftUI

struct FeatureFlagsView: View {
    private let featureFlags: any FeatureFlagProviding
    @Environment(\.settingsStore) private var settings

    init(featureFlags: any FeatureFlagProviding) {
        self.featureFlags = featureFlags
    }

    var body: some View {
        Form {
            ForEach(FeatureStage.allCases, id: \.self) { stage in
                featureSection(for: stage)
            }
            Section {
                Button("Reset All to Defaults", role: .destructive) {
                    featureFlags.resetAll()
                }
            }
        }
        .navigationTitle("Feature Flags")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func featureSection(for stage: FeatureStage) -> some View {
        let features = FeatureCatalog.all.filter { $0.stage == stage }
        if !features.isEmpty {
            Section {
                ForEach(features, id: \.key) { feature in
                    FeatureFlagRow(feature: feature, featureFlags: featureFlags, settings: settings)
                }
            } header: {
                Text(stage.displayTitle)
            }
        }
    }
}

private struct FeatureFlagRow: View {
    let feature: Feature
    let featureFlags: any FeatureFlagProviding
    let settings: SettingsStore?

    var body: some View {
        let isEnabled = featureFlags.isEnabled(feature)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                    Text(feature.key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
                Spacer()
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(isEnabled ? Color.green : Color.secondary)
                    .accessibilityLabel(isEnabled ? "Resolved: enabled" : "Resolved: disabled")
            }
            Text(feature.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if isEnabled, let statusText {
                Label(statusText, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.tint)
            }
            Picker("Override", selection: overrideBinding(for: feature)) {
                Text("Default").tag(FeatureOverride.useDefault)
                Text("Enabled").tag(FeatureOverride.enabled)
                Text("Disabled").tag(FeatureOverride.disabled)
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }

    /// A live "this flag is actually doing something" line, answering the
    /// question "did enabling this do anything?" without having to leave
    /// Settings to check. Only defined for flags with an observable runtime
    /// effect here; other flags just show the toggle state above.
    private var statusText: String? {
        switch feature {
        case FeatureCatalog.geoStations:
            if settings?.isPreciseGeoStationLocationEnabled == true {
                return "Filtering by your precise location"
            }
            let regionName = Locale.current.region
                .flatMap { Locale.current.localizedString(forRegionCode: $0.identifier) }
            return regionName.map { "Showing stations from \($0)" }
                ?? "Filtering stations by your region"
        default:
            return nil
        }
    }

    private func overrideBinding(for feature: Feature) -> Binding<FeatureOverride> {
        Binding(
            get: { featureFlags.override(for: feature) },
            set: { featureFlags.setOverride($0, for: feature) }
        )
    }
}

private extension FeatureStage {
    var displayTitle: String {
        switch self {
        case .internalOnly: "Internal"
        case .beta: "Beta"
        case .released: "Released"
        }
    }
}
#endif
