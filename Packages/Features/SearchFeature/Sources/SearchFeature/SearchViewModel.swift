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

@Observable
public final class SearchViewModel {
    public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    public private(set) var phase: SearchPhase = .idle
    public private(set) var genres: [Genre] = []

    @ObservationIgnored private let directory: any RadioDirectoryProviding
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(directory: any RadioDirectoryProviding) {
        self.directory = directory
    }

    public func loadGenres() async {
        genres = (try? await directory.genres()) ?? []
    }

    public func selectGenre(_ genre: Genre) {
        query = genre.name
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            phase = .idle
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard Task.isCancelled == false, let self else { return }
            // Only show the spinner once the debounce actually fires; setting it
            // per keystroke makes results flicker while the user is typing.
            self.phase = .searching
            await self.performSearch(trimmed)
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
