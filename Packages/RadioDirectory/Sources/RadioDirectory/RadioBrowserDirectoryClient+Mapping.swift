import Foundation

// Radio-Browser DTO -> domain `Station` mapping, split out of
// RadioBrowserDirectoryClient.swift when that file crossed SwiftLint's 400-line
// `file_length` limit. It is a clean seam rather than an arbitrary cut: purely a
// translation layer that touches no actor state, performs no I/O, and whose
// every member is already `static`. Splitting it is also what let the client
// file drop its `swiftlint:disable type_body_length` instead of carrying a
// suppression — the house remedy for a long type is a real seam, not a disable.
extension RadioBrowserDirectoryClient {
    static func station(from dto: RadioBrowserStation) -> Station? {
        let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedName = StationNameFormatter.normalize(name)
        guard normalizedName.isEmpty == false, dto.stationuuid.isEmpty == false else {
            return nil
        }

        // `url_resolved` is the directly playable stream; fall back to `url`.
        let rawStream = [dto.urlResolved, dto.url]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false }
        guard let rawStream, let streamURL = URL(string: rawStream) else {
            return nil
        }

        return Station(
            id: dto.stationuuid,
            name: normalizedName,
            genre: genre(from: dto),
            tags: tags(from: dto),
            country: normalizedValue(dto.country),
            codec: normalizedValue(dto.codec),
            language: normalizedValue(dto.language),
            listenerCount: 0,
            bitrate: (dto.bitrate ?? 0) > 0 ? dto.bitrate : nil,
            clickTrend: dto.clicktrend,
            votes: dto.votes,
            artworkURL: artworkURL(from: dto.favicon),
            preferredStreamURL: streamURL
        )
    }

    static func genre(from dto: RadioBrowserStation) -> String {
        let firstTag = dto.tags?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false }

        if let firstTag {
            return firstTag.capitalized
        }

        let country = dto.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return country.isEmpty ? "Radio" : country
    }

    static func tags(from dto: RadioBrowserStation) -> [String]? {
        Station.tags(fromCSV: dto.tags)
    }

    static func normalizedValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Favicons are frequently plain http://, which ATS blocks for image loads
    /// (the app's ATS exception covers AV media only). Upgrading to https is a
    /// best-effort heuristic — if the host doesn't support it, the artwork
    /// placeholder shows instead.
    static func artworkURL(from favicon: String?) -> URL? {
        let trimmed = favicon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false, var components = URLComponents(string: trimmed) else {
            return nil
        }

        if components.scheme?.caseInsensitiveCompare("http") == .orderedSame {
            components.scheme = "https"
            // `http://host:8080` → `https://host` rather than preserving an
            // arbitrary cleartext port that is unlikely to serve TLS.
            components.port = nil
        }

        return components.url
    }
}
