import Accelerate
import FactoryKit
import Foundation

public struct StationRecommendation: Equatable, Sendable {
    public let station: Station
    public let score: Double

    public init(station: Station, score: Double) {
        self.station = station
        self.score = score
    }
}

public protocol RecommendationServicing: Sendable {
    func moreLikeThis(
        from history: [Station],
        candidates: [Station],
        limit: Int
    ) -> [StationRecommendation]
}

public enum RecommendationHashing {
    public static let fnvOffsetBase: UInt64 = 14695981039346656037
    public static let fnvPrime: UInt64 = 1099511628211
    /// ASCII `|`, used as a stable boundary marker between adjacent station IDs.
    public static let segmentSeparator: UInt8 = 124

    public static func stableHash(_ value: String, seed: UInt64 = fnvOffsetBase) -> UInt64 {
        value.utf8.reduce(seed) { hash, byte in
            (hash ^ UInt64(byte)) &* fnvPrime
        }
    }

    public static func stableHash(segments: [String]) -> UInt64 {
        segments.reduce(fnvOffsetBase) { hash, segment in
            let next = stableHash(segment, seed: hash)
            return (next ^ UInt64(segmentSeparator)) &* fnvPrime
        }
    }
}

public struct RecommendationService: RecommendationServicing, Sendable {
    private enum VectorLayout {
        /// Hash-bucket dimensions for text tokens (genre/tags/country/language/codec).
        static let hashedTokenSlots = 92
        /// Total vector width; slots 92-95 are numeric/codec indicator channels.
        static let totalDimensions = 96
        /// Radio-Browser bitrates are typically <=320kbps; clamp at this ceiling.
        static let bitrateNormalizationCeiling: Float = 320
    }

    public struct Configuration: Equatable, Sendable {
        public let popularityWeight: Double

        public init(popularityWeight: Double = 0.2) {
            self.popularityWeight = min(max(popularityWeight, 0), 1)
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func moreLikeThis(
        from history: [Station],
        candidates: [Station],
        limit: Int
    ) -> [StationRecommendation] {
        guard limit > 0, !history.isEmpty, !candidates.isEmpty else { return [] }

        let historyIDs = Set(history.map(\.id))
        let scoredCandidates = candidates.filter { !historyIDs.contains($0.id) }
        guard !scoredCandidates.isEmpty else { return [] }

        let popularityScores = normalizedPopularityScores(for: scoredCandidates)
        let recencyWeights = recencyWeights(for: history.count)
        let historyVectors = history.map(stationVector(from:))

        let ranked = scoredCandidates.enumerated().map { index, station -> StationRecommendation in
            let candidateVector = stationVector(from: station)
            let similarity = zip(historyVectors, recencyWeights).reduce(0.0) { partial, pair in
                partial + cosineSimilarity(candidateVector, pair.0) * pair.1
            }
            let popularity = popularityScores[index]
            let blended = (1 - configuration.popularityWeight) * similarity
                + configuration.popularityWeight * popularity
            return StationRecommendation(station: station, score: blended)
        }

        return Array(ranked.sorted {
            if $0.score == $1.score {
                // Station UUID/name keys are stable and available in every result.
                return $0.station.id < $1.station.id
            }
            return $0.score > $1.score
        }.prefix(limit))
    }

    private func normalizedPopularityScores(for stations: [Station]) -> [Double] {
        let rawScores = stations.map { station in
            let clickTrend = Double(max(station.clickTrend ?? 0, 0))
            let votes = Double(max(station.votes ?? 0, 0))
            return log1p(clickTrend) + log1p(votes)
        }
        guard let min = rawScores.min(), let max = rawScores.max(), max > min else {
            return Array(repeating: 0, count: rawScores.count)
        }

        return rawScores.map { ($0 - min) / (max - min) }
    }

    private func recencyWeights(for count: Int) -> [Double] {
        let descending = (1...count).reversed().map(Double.init)
        let total = descending.reduce(0, +)
        guard total > 0 else { return Array(repeating: 0, count: count) }
        return descending.map { $0 / total }
    }

    private func stationVector(from station: Station) -> [Float] {
        var vector = Array(repeating: Float(0), count: VectorLayout.totalDimensions)
        let codec = station.codec?.uppercased()

        for token in stationTokens(from: station) {
            let index = Int(stableHash(token) % UInt64(VectorLayout.hashedTokenSlots))
            vector[index] += 1
        }

        if let bitrate = station.bitrate, bitrate > 0 {
            vector[92] = min(Float(bitrate) / VectorLayout.bitrateNormalizationCeiling, 1)
        }

        vector[93] = codec?.contains("AAC") == true ? 1 : 0
        vector[94] = codec?.contains("MP3") == true ? 1 : 0
        vector[95] = codec?.contains("OPUS") == true ? 1 : 0
        return vector
    }

    private func stationTokens(from station: Station) -> [String] {
        var tokens: [String] = []
        tokens.append("genre:\(normalizedToken(station.genre))")
        tokens.append(contentsOf: (station.tags ?? []).map { "tag:\(normalizedToken($0))" })

        if let country = station.country {
            tokens.append("country:\(normalizedToken(country))")
        }
        if let language = station.language {
            tokens.append("language:\(normalizedToken(language))")
        }
        if let codec = station.codec {
            tokens.append("codec:\(normalizedToken(codec))")
        }
        return tokens
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        let dot = vDSP.dot(lhs, rhs)
        let lhsMagnitude = sqrt(vDSP.dot(lhs, lhs))
        let rhsMagnitude = sqrt(vDSP.dot(rhs, rhs))
        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return 0 }
        return Double(dot / (lhsMagnitude * rhsMagnitude))
    }

    private func normalizedToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// FNV-1a (64-bit), deterministic across launches/processes.
    /// Used so hashed-token vector slots are stable across runs/devices; Swift's
    /// standard `Hasher` intentionally randomizes seeds between processes.
    private func stableHash(_ value: String) -> UInt64 {
        RecommendationHashing.stableHash(value)
    }
}

public extension Container {
    var recommendationService: Factory<any RecommendationServicing> {
        self { RecommendationService() }
            .scope(.singleton)
            .onPreview { RecommendationService() }
            .onTest { RecommendationService() }
    }
}

public func sharedRecommendationService() -> any RecommendationServicing {
    Container.shared.recommendationService()
}
