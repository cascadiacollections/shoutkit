import Foundation

public struct RadioBrowserGeoFilter: Equatable, Sendable {
    public let countryCode: String?
    public let languageCode: String?

    public init(countryCode: String?, languageCode: String?) {
        let normalizedCountryCode = countryCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let normalizedLanguageCode = languageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        self.countryCode = normalizedCountryCode?.isEmpty == false ? normalizedCountryCode : nil
        self.languageCode = normalizedLanguageCode?.isEmpty == false ? normalizedLanguageCode : nil
    }

    public init(locale: Locale, countryCodeOverride: String? = nil) {
        self.init(
            countryCode: countryCodeOverride ?? locale.region?.identifier,
            languageCode: locale.language.languageCode?.identifier
        )
    }

    /// Stable key for this filter, used to scope persisted directory snapshots
    /// so content captured for one country/language isn't served after the filter
    /// changes — travel, or the geo-stations flag being toggled.
    public var snapshotIdentity: String {
        "country=\(countryCode ?? "any");language=\(languageCode ?? "any")"
    }

    var queryItemSets: [[URLQueryItem]] {
        var queryItemSets: [[URLQueryItem]] = []

        if let countryCode {
            queryItemSets.append([URLQueryItem(name: "countrycode", value: countryCode)])
        }

        if let languageCode {
            queryItemSets.append([URLQueryItem(name: "language", value: languageCode)])
        }

        if queryItemSets.isEmpty {
            queryItemSets.append([])
        }

        return queryItemSets
    }
}

public protocol RadioBrowserGeoFilterProviding: Sendable {
    func currentGeoFilter() async -> RadioBrowserGeoFilter?
}

public actor MutableRadioBrowserGeoFilterProvider: RadioBrowserGeoFilterProviding {
    private var geoFilter: RadioBrowserGeoFilter?

    public init(initialGeoFilter: RadioBrowserGeoFilter? = nil) {
        geoFilter = initialGeoFilter
    }

    public func currentGeoFilter() async -> RadioBrowserGeoFilter? {
        geoFilter
    }

    public func setCurrentGeoFilter(_ geoFilter: RadioBrowserGeoFilter?) {
        self.geoFilter = geoFilter
    }
}
