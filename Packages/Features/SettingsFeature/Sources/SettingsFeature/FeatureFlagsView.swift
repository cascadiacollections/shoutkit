import FeatureFlags
import SwiftUI

struct FeatureFlagsView: View {
    private let featureFlags: DefaultsFeatureFlagService

    init(featureFlags: DefaultsFeatureFlagService) {
        self.featureFlags = featureFlags
    }

    var body: some View {
        Form {
            Section {
                ForEach(FeatureCatalog.all, id: \.key) { feature in
                    Toggle(isOn: isEnabledBinding(for: feature)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(feature.title)
                            Text(feature.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Flags")
            } footer: {
                Text("Turn a feature on or off. Use Reset to return all flags to their defaults.")
            }

            Section {
                Button("Reset All to Defaults") {
                    featureFlags.resetAll()
                }
            }
        }
        .navigationTitle("Feature Flags")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isEnabledBinding(for feature: Feature) -> Binding<Bool> {
        Binding(
            get: { featureFlags.isEnabled(feature) },
            set: { isEnabled in
                featureFlags.setOverride(isEnabled ? .enabled : .disabled, for: feature)
            }
        )
    }
}
