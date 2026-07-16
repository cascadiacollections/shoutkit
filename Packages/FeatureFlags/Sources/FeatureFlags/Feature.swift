import Foundation

public enum FeatureStage: String, Codable, CaseIterable, Sendable {
    case internalOnly
    case beta
    case released
}

public enum FeatureOverride: String, Codable, CaseIterable, Sendable {
    case useDefault
    case enabled
    case disabled
}

public struct Feature: Hashable, Sendable {
    public let key: String
    public let title: String
    public let summary: String
    public let stage: FeatureStage
    public let defaultEnabled: Bool

    public init(
        key: String,
        title: String,
        summary: String,
        stage: FeatureStage,
        defaultEnabled: Bool
    ) {
        self.key = key
        self.title = title
        self.summary = summary
        self.stage = stage
        self.defaultEnabled = defaultEnabled
    }
}

public enum FeatureCatalog {
    public static let all: [Feature] = [
        Feature(
            key: "diagnostics",
            title: "Diagnostics",
            summary: "Enable optional local MetricKit diagnostics collection.",
            stage: .internalOnly,
            defaultEnabled: false
        ),
        Feature(
            key: "geoStations",
            title: "Geo Stations",
            summary: "Placeholder flag for geography-aware station discovery.",
            stage: .internalOnly,
            defaultEnabled: false
        ),
        Feature(
            key: "recommendations",
            title: "Recommendations",
            summary: "Placeholder flag for personalized station recommendations.",
            stage: .internalOnly,
            defaultEnabled: false
        )
    ]

    public static let diagnostics: Feature = {
        guard let feature = all.first(where: { $0.key == "diagnostics" }) else {
            preconditionFailure("Missing diagnostics feature in FeatureCatalog")
        }
        return feature
    }()
}
