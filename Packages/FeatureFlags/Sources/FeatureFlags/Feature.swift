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
    private static let diagnosticsFeature = Feature(
        key: "diagnostics",
        title: "Diagnostics",
        summary: "Enable optional local MetricKit diagnostics collection.",
        stage: .internalOnly,
        defaultEnabled: false
    )

    public static let geoStations = Feature(
        key: "geoStations",
        title: "Geo Stations",
        summary: "Filter Radio-Browser discovery by region; optional precise location is separate and off by default.",
        stage: .internalOnly,
        defaultEnabled: false
    )

    public static let recommendations = Feature(
        key: "recommendations",
        title: "Recommendations",
        summary: "On-device \u{201C}More Like This\u{201D} station recommendations from play history.",
        stage: .internalOnly,
        defaultEnabled: false
    )

    public static let prewarmStations = Feature(
        key: "prewarmStations",
        title: "Prewarm Stations",
        summary: "At launch, warm the network path (DNS/TLS) to your top stations so playback starts faster.",
        stage: .internalOnly,
        defaultEnabled: false
    )

    public static let liveActivity = Feature(
        key: "liveActivity",
        title: "Live Activity",
        summary: "Show a now-playing Live Activity on the Lock Screen and Dynamic Island. "
            + "Off by default: its artwork can lag the current track, and it adds little "
            + "over the system Now Playing surface.",
        stage: .internalOnly,
        defaultEnabled: false
    )

    public static let all: [Feature] = [
        diagnosticsFeature,
        geoStations,
        recommendations,
        prewarmStations,
        liveActivity
    ]

    public static let diagnostics = diagnosticsFeature
}
