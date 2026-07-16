import Foundation
import Testing
@testable import RadioDirectory

// Fixtures live at file scope (plain Station initializers — a shared helper
// function would trip the function_parameter_count rule, which exempts
// inits) so each test body stays inside the lint function-body budget.
private let rankingHistory = [
    Station(
        id: "h1",
        name: "History One",
        genre: "Electronic",
        tags: ["ambient", "downtempo"],
        country: "Canada",
        codec: "AAC",
        language: "English",
        listenerCount: 0,
        bitrate: 192
    )
]

/// "Far Match" deliberately shares nothing with the history station (note the
/// MP3 codec — a shared codec alone is enough signal to reorder candidates),
/// so content similarity should outweigh its higher popularity prior.
private let rankingCandidates = [
    Station(
        id: "c1",
        name: "Close Match",
        genre: "Electronic",
        tags: ["ambient", "chill"],
        country: "Canada",
        codec: "AAC",
        language: "English",
        listenerCount: 0,
        bitrate: 192,
        clickTrend: 10,
        votes: 20
    ),
    Station(
        id: "c2",
        name: "Medium Match",
        genre: "Electronic",
        tags: ["techno"],
        country: "Germany",
        codec: "MP3",
        language: "German",
        listenerCount: 0,
        bitrate: 128,
        clickTrend: 50,
        votes: 60
    ),
    Station(
        id: "c3",
        name: "Far Match",
        genre: "Talk",
        tags: ["news"],
        country: "Japan",
        codec: "MP3",
        language: "Japanese",
        listenerCount: 0,
        bitrate: 64,
        clickTrend: 200,
        votes: 200
    )
]

private let popularityHistory = [
    Station(
        id: "h1",
        name: "History",
        genre: "Jazz",
        tags: ["jazz"],
        country: "US",
        codec: "AAC",
        language: "English",
        listenerCount: 0,
        bitrate: 128
    )
]

private let popularityCandidates = [
    Station(
        id: "low-pop",
        name: "Closer Content",
        genre: "Jazz",
        tags: ["jazz"],
        country: "US",
        codec: "AAC",
        language: "English",
        listenerCount: 0,
        bitrate: 128,
        clickTrend: 1,
        votes: 1
    ),
    Station(
        id: "high-pop",
        name: "Higher Popularity",
        genre: "Rock",
        tags: ["rock"],
        country: "US",
        codec: "MP3",
        language: "English",
        listenerCount: 0,
        bitrate: 128,
        clickTrend: 500,
        votes: 500
    )
]

@Test
func deterministicRankingForFixedInputs() {
    let service = RecommendationService()

    let first = service.moreLikeThis(from: rankingHistory, candidates: rankingCandidates, limit: 3)
    let second = service.moreLikeThis(from: rankingHistory, candidates: rankingCandidates, limit: 3)

    #expect(first == second)
    #expect(first.map(\.station.id) == ["c1", "c2", "c3"])
}

@Test
func popularityPriorCanChangeOrder() {
    let service = RecommendationService(configuration: .init(popularityWeight: 0.7))

    let ranked = service.moreLikeThis(from: popularityHistory, candidates: popularityCandidates, limit: 2)
    #expect(ranked.map(\.station.id) == ["high-pop", "low-pop"])
}
