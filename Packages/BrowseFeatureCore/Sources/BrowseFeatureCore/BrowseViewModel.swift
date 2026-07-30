import FactoryKit
import Foundation
import Observation
import RadioDirectory

/// Where the content on screen came from, so a surface can be honest about
/// showing yesterday's stations without turning it into an error.
public enum BrowseContentOrigin: Equatable, Sendable {
    /// Fetched from the directory this session.
    case live
    /// Restored from the on-disk snapshot captured at this date.
    case saved(capturedAt: Date?)
}

public struct BrowseContent: Equatable, Sendable {
    public let spotlight: Station?
    public let stations: [Station]
    public let genres: [Genre]
    public let origin: BrowseContentOrigin

    public init(
        spotlight: Station?,
        stations: [Station],
        genres: [Genre],
        origin: BrowseContentOrigin = .live
    ) {
        self.spotlight = spotlight
        self.stations = stations
        self.genres = genres
        self.origin = origin
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

/// What prompted a refresh, which decides whether saved content may stand in for
/// a directory fetch.
public enum BrowseRefreshSource: Equatable, Sendable {
    /// A surface appearing. Paints the saved snapshot first so the list is there
    /// immediately, and skips the fetch entirely while that snapshot is inside its
    /// stability window.
    case automatic
    /// Pull-to-refresh, or a "Try Again" tap. Always reaches the directory.
    case userInitiated
}

@Observable
public final class BrowseViewModel {
    private enum Configuration {
        static let topStationsLimit = 24
        static let genreStationsLimit = 30
    }

    public private(set) var phase: BrowsePhase = .loading
    public private(set) var genresError: RadioDirectoryError?
    /// Set when a directory fetch failed while content was already on screen. The
    /// surfaces keep that content and note it's not live, instead of replacing a
    /// usable station list with an error page.
    public private(set) var refreshError: RadioDirectoryError?

    /// Active genre filter. Selecting one queries the directory for that genre —
    /// the top-stations list is far too small to filter client-side.
    public private(set) var selectedGenre: String?
    public private(set) var genrePhase: GenreStationsPhase?

    @ObservationIgnored private let directory: any RadioDirectoryProviding
    @ObservationIgnored private let discoveryCache: (any DirectoryDiscoveryCaching)?
    @ObservationIgnored private var genreTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    public init(
        directory: any RadioDirectoryProviding = Container.shared.radioDirectory(),
        discoveryCache: (any DirectoryDiscoveryCaching)? = Container.shared.directoryDiscoveryCache()
    ) {
        self.directory = directory
        self.discoveryCache = discoveryCache
    }

    public func refresh(source: BrowseRefreshSource = .automatic) async {
        refreshGeneration += 1
        let generation = refreshGeneration

        // Saved stations first: a cold launch — or one where the connection is
        // about to disappear — shows the list it showed last time instead of a
        // spinner, and a snapshot inside its stability window is the whole answer.
        if source == .automatic {
            let savedContentIsFresh = await presentSavedContent(generation: generation)
            if savedContentIsFresh { return }
        }

        if case .loaded = phase {} else {
            phase = .loading
        }
        genresError = nil

        if source == .userInitiated {
            // Otherwise the short in-memory window would answer a pull-to-refresh
            // without going anywhere near the directory.
            await discoveryCache?.invalidateMemoryCache()
        }

        await loadLiveContent(generation: generation)
    }

    /// Renders the persisted snapshot, if there is one worth rendering. Returns
    /// whether it's fresh enough to stand alone — in which case the caller skips
    /// the directory fetch for this pass.
    private func presentSavedContent(generation: Int) async -> Bool {
        guard let discoveryCache else { return false }
        guard let state = await discoveryCache.discoverySnapshotState() else { return false }
        let savedStations = state.snapshot.savedStations
        guard savedStations.isEmpty == false else { return false }
        // A newer refresh started while the snapshot was being read.
        guard refreshGeneration == generation else { return false }

        phase = .loaded(
            BrowseContent(
                spotlight: savedStations.first,
                stations: savedStations,
                genres: state.snapshot.savedGenres,
                origin: .saved(capturedAt: state.snapshot.capturedAt)
            )
        )
        genresError = nil
        refreshError = nil
        return state.isFresh
    }

    private func loadLiveContent(generation: Int) async {
        // Issue both discovery calls concurrently — they're independent, and
        // serializing them adds a full round-trip to first paint. Top stations
        // is fatal to the screen; genres degrades softly to an empty strip. In
        // the empty/failure paths the un-awaited genres `async let` is
        // auto-cancelled at scope exit.
        async let stationsResult = directory.topStations(limit: Configuration.topStationsLimit)
        async let genresResult = Self.loadGenres(from: directory)

        do {
            let stations = try await stationsResult
            guard refreshGeneration == generation else { return }

            guard stations.isEmpty == false else {
                // Same reasoning as a failed fetch: don't blank a station list
                // that's already on screen. An answered-but-empty directory is
                // only worth reporting when there's nothing to fall back to.
                if case .loaded = phase {} else {
                    phase = .empty
                }
                return
            }

            let (genres, genresError) = await genresResult
            guard refreshGeneration == generation else { return }
            self.genresError = genresError
            refreshError = nil

            phase = .loaded(
                BrowseContent(
                    spotlight: stations.first,
                    stations: stations,
                    genres: genres,
                    origin: .live
                )
            )
        } catch let error as RadioDirectoryError {
            guard refreshGeneration == generation else { return }
            handleRefreshFailure(error)
        } catch {
            guard refreshGeneration == generation else { return }
            handleRefreshFailure(.transport(error.localizedDescription))
        }
    }

    /// Stations already on screen — saved from a previous launch, or fetched
    /// earlier this session — outlive a failed fetch. They were playable the last
    /// time the directory answered, and the likely cause is a missing connection,
    /// not a broken app. Only a screen with nothing on it becomes an error.
    private func handleRefreshFailure(_ error: RadioDirectoryError) {
        if case .loaded = phase {
            refreshError = error
        } else {
            phase = .failed(error)
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
                let stations = try await directory.stations(
                    inGenre: genre,
                    limit: Configuration.genreStationsLimit
                )
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
