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

    public init(directory: any RadioDirectoryProviding = PreviewRadioDirectory()) {
        self.directory = directory
    }

    public func refresh() async {
        if case .loaded = phase {} else {
            phase = .loading
        }
        genresError = nil

        do {
            let stations = try await directory.topStations(limit: 24)

            guard stations.isEmpty == false else {
                phase = .empty
                return
            }

            let genres: [Genre]
            do {
                genres = try await directory.genres()
            } catch let error as RadioDirectoryError {
                genresError = error
                genres = []
            } catch {
                genresError = .transport(error.localizedDescription)
                genres = []
            }

            let content = BrowseContent(
                spotlight: stations.first,
                stations: stations,
                genres: genres
            )
            phase = .loaded(content)
        } catch let error as RadioDirectoryError {
            phase = .failed(error)
        } catch {
            phase = .failed(.transport(error.localizedDescription))
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
