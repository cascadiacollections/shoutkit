import Foundation

public struct StationSearchFilters: Codable, Equatable, Sendable {
    public var bitrateMin: Int?
    public var bitrateMax: Int?
    public var tag: String?
    public var countryCode: String?

    public init(
        bitrateMin: Int? = nil,
        bitrateMax: Int? = nil,
        tag: String? = nil,
        countryCode: String? = nil
    ) {
        self.bitrateMin = bitrateMin
        self.bitrateMax = bitrateMax
        self.tag = Self.normalizedText(tag)
        self.countryCode = Self.normalizedCountryCode(countryCode)
    }

    public static let none = StationSearchFilters()

    public var isActive: Bool {
        bitrateMin != nil || bitrateMax != nil || tag != nil || countryCode != nil
    }

    public var normalized: StationSearchFilters {
        var normalized = StationSearchFilters(
            bitrateMin: bitrateMin,
            bitrateMax: bitrateMax,
            tag: tag,
            countryCode: countryCode
        )
        if let min = normalized.bitrateMin, let max = normalized.bitrateMax, min > max {
            normalized.bitrateMax = min
        }
        return normalized
    }

    public func matches(_ station: Station) -> Bool {
        matchesBitrate(station.bitrate)
            && matchesTag(station)
            && matchesCountry(station.country)
    }

    public func apply(to stations: [Station]) -> [Station] {
        stations.filter(matches)
    }

    private func matchesBitrate(_ bitrate: Int?) -> Bool {
        if let bitrateMin, let bitrate, bitrate < bitrateMin {
            return false
        }
        if let bitrateMax, let bitrate, bitrate > bitrateMax {
            return false
        }
        // Unknown bitrate (nil) is not a positive failure.
        return true
    }

    private func matchesTag(_ station: Station) -> Bool {
        guard let tag else { return true }
        if station.genre.localizedCaseInsensitiveContains(tag) {
            return true
        }
        guard let stationTags = station.tags else {
            return false
        }
        return stationTags.contains { $0.localizedCaseInsensitiveContains(tag) }
    }

    private func matchesCountry(_ country: String?) -> Bool {
        guard let countryCode else { return true }
        guard let country else {
            // Missing country metadata is not a positive failure.
            return true
        }

        let normalizedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedCountry.isEmpty == false else {
            return true
        }

        if normalizedCountry == countryCode.lowercased() {
            return true
        }

        let regionNames = [
            Locale.current.localizedString(forRegionCode: countryCode),
            Locale(identifier: "en_US_POSIX").localizedString(forRegionCode: countryCode)
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        return regionNames.contains(normalizedCountry)
    }

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func normalizedCountryCode(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
