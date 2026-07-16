import Foundation
import Testing
@testable import RadioDirectory

@Test
func deterministicRankingForFixedInputs() {
    let service = RecommendationService()
    let history = [
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
    let candidates = [
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
            codec: "AAC",
            language: "Japanese",
            listenerCount: 0,
            bitrate: 64,
            clickTrend: 200,
            votes: 200
        )
    ]

    let first = service.moreLikeThis(from: history, candidates: candidates, limit: 3)
    let second = service.moreLikeThis(from: history, candidates: candidates, limit: 3)

    #expect(first == second)
    #expect(first.map(\.station.id) == ["c1", "c2", "c3"])
}

@Test
func popularityPriorCanChangeOrder() {
    let service = RecommendationService(configuration: .init(popularityWeight: 0.7))
    let history = [
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
    let candidates = [
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

    let ranked = service.moreLikeThis(from: history, candidates: candidates, limit: 2)
    #expect(ranked.map(\.station.id) == ["high-pop", "low-pop"])
}
