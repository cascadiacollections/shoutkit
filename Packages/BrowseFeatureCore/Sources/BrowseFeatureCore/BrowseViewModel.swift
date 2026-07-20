import FactoryKit
import Observation
import RadioDirectory

public struct BrowseContent: Equatable, Sendable {
    public let spotlight: Station?
    public let stations: [Station]
    public let genres: [Genre]

    public init(spotlight: Station?, stations: [Station], genres: [Genre]) {
        self.spotlight = spotlight
        self.stations = stations
        self.genres = genres
    }
}

public enum BrowsePhase: Equatable, Sendable {
    case loading
    case empty
    case loaded(BrowseContent)
    case failed(RadioDirectoryError)
}

public enum GenreStationsPhase: Equatable, Sendable {
    case loading
    case loaded([Station])
    case failed(RadioDirectoryError)
}

@Observable
public final class BrowseViewModel {
    public private(set) var phase: BrowsePhase = .loading
    public private(set) var genresError: RadioDirectoryError?

    /// Active genre filter. Selecting one queries the directory for that genre —
    /// the top-stations list is far too small to filter client-side.
    public private(set) var selectedGenre: String?
    public private(set) var genrePhase: GenreStationsPhase?

    @ObservationIgnored private let directory: any RadioDirectoryProviding
    @ObservationIgnored private var genreTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    public init(directory: any RadioDirectoryProviding = Container.shared.radioDirectory()) {
        self.directory = directory
    }

    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration

        if case .loaded = phase {} else {
            phase = .loading
        }
        genresError = nil

        // Issue both discovery calls concurrently — they're independent, and
        // serializing them adds a full round-trip to first paint. Top stations
        // is fatal to the screen; genres degrades softly to an empty strip. In
        // the empty/failure paths the un-awaited genres `async let` is
        // auto-cancelled at scope exit.
        async let stationsResult = directory.topStations(limit: 24)
        async let genresResult = Self.loadGenres(from: directory)

        do {
            let stations = try await stationsResult
            guard refreshGeneration == generation else { return }

            guard stations.isEmpty == false else {
                phase = .empty
                return
            }

            let (genres, genresError) = await genresResult
            guard refreshGeneration == generation else { return }
            self.genresError = genresError

            let content = BrowseContent(
                spotlight: stations.first,
                stations: stations,
                genres: genres
            )
            phase = .loaded(content)
        } catch let error as RadioDirectoryError {
            guard refreshGeneration == generation else { return }
            phase = .failed(error)
        } catch {
            guard refreshGeneration == generation else { return }
            phase = .failed(.transport(error.localizedDescription))
        }
    }

    /// Fetches genres, folding any error into the return value instead of
    /// throwing — genres are non-fatal to the browse screen, so `refresh()`
    /// can run this concurrently with the fatal top-stations fetch.
    private static func loadGenres(
        from directory: any RadioDirectoryProviding
    ) async -> ([Genre], RadioDirectoryError?) {
        do {
            return (try await directory.genres(), nil)
        } catch let error as RadioDirectoryError {
            return ([], error)
        } catch {
            return ([], .transport(error.localizedDescription))
        }
    }

    public func toggleGenreFilter(_ genre: String) {
        genreTask?.cancel()

        if selectedGenre == genre {
            selectedGenre = nil
            genrePhase = nil
            return
        }

        selectedGenre = genre
        genrePhase = .loading

        genreTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stations = try await directory.stations(inGenre: genre, limit: 30)
                guard Task.isCancelled == false, self.selectedGenre == genre else { return }
                self.genrePhase = .loaded(stations)
            } catch let error as RadioDirectoryError {
                guard Task.isCancelled == false, self.selectedGenre == genre else { return }
                self.genrePhase = .failed(error)
            } catch {
                guard Task.isCancelled == false, self.selectedGenre == genre else { return }
                self.genrePhase = .failed(.transport(error.localizedDescription))
            }
        }
    }
}
