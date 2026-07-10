import AsyncAlgorithms
import Foundation
import Observation
import RadioDirectory

public enum SearchPhase: Equatable, Sendable {
    case idle
    case searching
    case results([Station])
    case empty
    case failed(RadioDirectoryError)
}

// Explicitly @MainActor (not just the target's default isolation): the
// isolated deinit below requires the class itself to carry the actor
// annotation.
@MainActor
@Observable
public final class SearchViewModel {
    public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            searchTask?.cancel()

            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // Clearing resets instantly; only real queries wait out the
                // debounce. The empty value still flows through the stream so
                // it supersedes any keystroke waiting in the debounce window.
                phase = .idle
            }
            queries.yield(trimmed)
        }
    }

    public private(set) var phase: SearchPhase = .idle
    public private(set) var genres: [Genre] = []

    @ObservationIgnored private let directory: any RadioDirectoryProviding
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private let queries: AsyncStream<String>.Continuation

    public init(directory: any RadioDirectoryProviding) {
        self.directory = directory

        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        queries = continuation
        debounceTask = Task { [weak self] in
            // The debounce emits only the latest value after 300 ms of
            // keyboard quiet, so a superseded keystroke never hits the network.
            for await query in stream.debounce(for: .milliseconds(300)) {
                guard let self else { return }
                guard query.isEmpty == false else { continue }
                self.runSearch(query)
            }
        }
    }

    isolated deinit {
        searchTask?.cancel()
        debounceTask?.cancel()
    }

    public func loadGenres() async {
        genres = (try? await directory.genres()) ?? []
    }

    public func selectGenre(_ genre: Genre) {
        query = genre.name
    }

    private func runSearch(_ query: String) {
        searchTask?.cancel()
        // Only show the spinner once the debounce actually fires; setting it
        // per keystroke makes results flicker while the user is typing.
        phase = .searching
        searchTask = Task { [weak self] in
            await self?.performSearch(query)
        }
    }

    private func performSearch(_ query: String) async {
        do {
            let stations = try await directory.searchStations(matching: query, limit: 40)
            guard Task.isCancelled == false else { return }
            phase = stations.isEmpty ? .empty : .results(stations)
        } catch {
            guard Task.isCancelled == false else { return }
            phase = .failed(error)
        }
    }
}
