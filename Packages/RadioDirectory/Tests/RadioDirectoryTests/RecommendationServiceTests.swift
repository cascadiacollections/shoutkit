import Foundation
import Testing
@testable import RadioDirectory

// Fixtures live at file scope so each test body stays inside the lint
// function-body budget.
private let rankingHistory = [
    makeStation(
        id: "h1",
        name: "History One",
        genre: "Electronic",
        tags: ["ambient", "downtempo"],
        country: "Canada",
        codec: "AAC",
        language: "English",
        bitrate: 192
    )
]

/// "Far Match" deliberately shares nothing with the history station (note the
/// MP3 codec — a shared codec alone is enough signal to reorder candidates),
/// so content similarity should outweigh its higher popularity prior.
private let rankingCandidates = [
    makeStation(
        id: "c1",
        name: "Close Match",
        genre: "Electronic",
        tags: ["ambient", "chill"],
        country: "Canada",
        codec: "AAC",
        language: "English",
        bitrate: 192,
        clickTrend: 10,
        votes: 20
    ),
    makeStation(
        id: "c2",
        name: "Medium Match",
        genre: "Electronic",
        tags: ["techno"],
        country: "Germany",
        codec: "MP3",
        language: "German",
        bitrate: 128,
        clickTrend: 50,
        votes: 60
    ),
    makeStation(
        id: "c3",
        name: "Far Match",
        genre: "Talk",
        tags: ["news"],
        country: "Japan",
        codec: "MP3",
        language: "Japanese",
        bitrate: 64,
        clickTrend: 200,
        votes: 200
    )
]

private func makeStation(
    id: String,
    name: String,
    genre: String,
    tags: [String],
    country: String,
    codec: String,
    language: String,
    bitrate: Int,
    clickTrend: Int? = nil,
    votes: Int? = nil
) -> Station {
    Station(
        id: id,
        name: name,
        genre: genre,
        tags: tags,
        country: country,
        codec: codec,
        language: language,
        listenerCount: 0,
        bitrate: bitrate,
        clickTrend: clickTrend,
        votes: votes
    )
}

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
    let history = [
        makeStation(
            id: "h1",
            name: "History",
            genre: "Jazz",
            tags: ["jazz"],
            country: "US",
            codec: "AAC",
            language: "English",
            bitrate: 128
        )
    ]
    let candidates = [
        makeStation(
            id: "low-pop",
            name: "Closer Content",
            genre: "Jazz",
            tags: ["jazz"],
            country: "US",
            codec: "AAC",
            language: "English",
            bitrate: 128,
            clickTrend: 1,
            votes: 1
        ),
        makeStation(
            id: "high-pop",
            name: "Higher Popularity",
            genre: "Rock",
            tags: ["rock"],
            country: "US",
            codec: "MP3",
            language: "English",
            bitrate: 128,
            clickTrend: 500,
            votes: 500
        )
    ]

    let ranked = service.moreLikeThis(from: history, candidates: candidates, limit: 2)
    #expect(ranked.map(\.station.id) == ["high-pop", "low-pop"])
}
