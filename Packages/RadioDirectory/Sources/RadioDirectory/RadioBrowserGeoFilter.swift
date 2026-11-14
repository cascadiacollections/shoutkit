import Foundation

/// The region ``RadioBrowserDirectoryClient`` favours when it lists top stations.
///
/// Country only. An earlier version also carried a language code and fell back to
/// Radio-Browser's `language` parameter, but that parameter matches language
/// *names* by substring, so `en` matched "english", "french" and "slovene" alike.
public struct RadioBrowserGeoFilter: Equatable, Sendable {
    /// ISO 3166-1 alpha-2, uppercased; `nil` when there is no usable region.
    public let countryCode: String?

    public init(countryCode: String?) {
        let normalized = countryCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        self.countryCode = normalized?.isEmpty == false ? normalized : nil
    }

    /// The region from `locale`, which is the device's region setting, not its
    /// location. Reading it needs no permission.
    public init(locale: Locale) {
        self.init(countryCode: locale.region?.identifier)
    }

    /// Stable key for this filter, used to scope persisted directory snapshots
    /// so stations saved for one region aren't shown after the region changes.
    public var snapshotIdentity: String {
        "country=\(countryCode ?? "any")"
    }
}

public protocol RadioBrowserGeoFilterProviding: Sendable {
    func currentGeoFilter() async -> RadioBrowserGeoFilter?
}

/// Follows the device's region setting as it is now, so changing the region in
/// Settings takes effect on the next refresh without relaunching.
public struct LocaleGeoFilterProvider: RadioBrowserGeoFilterProviding {
    public init() {}

    public func currentGeoFilter() async -> RadioBrowserGeoFilter? {
        RadioBrowserGeoFilter(locale: .autoupdatingCurrent)
    }
}

/// A provider whose filter is set explicitly — for tests and for apps that
/// choose the region themselves.
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
