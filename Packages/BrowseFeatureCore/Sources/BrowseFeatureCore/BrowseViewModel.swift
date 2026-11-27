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
        origin: BrowseContentOrigin = .live,
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
    /// immediately, and skips the station fetch while that snapshot is inside its
    /// stability window. A genre half that was never captured is still fetched.
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
    /// the top-stations list is far too small to filter client-side. Listen Now
    /// draws ``genrePhase`` in place of the popular grid while this is set.
    public private(set) var selectedGenre: String?
    public private(set) var genrePhase: GenreStationsPhase?

    @ObservationIgnored private let directory: any RadioDirectoryProviding
    @ObservationIgnored private let discoveryCache: any DirectoryDiscoveryCaching
    @ObservationIgnored private var genreTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    public init(
        directory: any RadioDirectoryProviding = Container.shared.radioDirectory(),
        discoveryCache: any DirectoryDiscoveryCaching = Container.shared.directoryDiscoveryCache(),
    ) {
        self.directory = directory
        self.discoveryCache = discoveryCache
    }

    public func refresh(source: BrowseRefreshSource = .automatic) async {
        refreshGeneration += 1
        let generation = refreshGeneration

        // Saved stations first: a cold launch — or one where the connection is
        // about to disappear — shows the list it showed last time instead of a
        // spinner, and a snapshot inside its stability window is the station list.
        if source == .automatic {
            let saved = await presentSavedContent(generation: generation)
            if saved.stationsAreFresh {
                // Genres are non-fatal, so a snapshot can be fresh for stations
                // while that half was never written. Fetching them here does not
                // refetch the station list, which would reshuffle it.
                if saved.needsGenres {
                    await fillInGenres(generation: generation)
                }
                return
            }
        }

        if case .loaded = phase {} else {
            phase = .loading
        }
        genresError = nil
        // Cleared here rather than only on success: while a retry is in flight the
        // "offline" note would otherwise still be claiming something this pass
        // hasn't established. It comes back if this fetch fails too.
        refreshError = nil

        if source == .userInitiated {
            // Otherwise the short in-memory window would answer a pull-to-refresh
            // without going anywhere near the directory.
            await discoveryCache.invalidateMemoryCache()
        }

        await loadLiveContent(generation: generation)
    }

    /// What an automatic refresh should do with a snapshot it was able to paint.
    private struct SavedContentDecision {
        var stationsAreFresh = false
        /// The station list can stand in, and the genre half was never captured.
        var needsGenres = false
    }

    /// Renders the persisted snapshot, if there is one worth rendering. A fresh
    /// station list lets the caller skip the directory's top-stations fetch.
    /// `needsGenres` is set when that list is fresh but the genre half is absent,
    /// so the strip is not left empty for the rest of the stability window.
    private func presentSavedContent(generation: Int) async -> SavedContentDecision {
        guard let state = await discoveryCache.discoverySnapshotState() else { return SavedContentDecision() }
        let savedStations = state.snapshot.savedStations
        guard savedStations.isEmpty == false else { return SavedContentDecision() }
        // A newer refresh started while the snapshot was being read.
        guard refreshGeneration == generation else { return SavedContentDecision() }

        phase = .loaded(
            BrowseContent(
                spotlight: savedStations.first,
                stations: savedStations,
                genres: state.snapshot.savedGenres,
                // The stations' own capture date, not the snapshot's oldest half:
                // the note this feeds is about the stations, so older genres (from
                // a genres fetch that failed on its own) mustn't backdate it.
                origin: .saved(capturedAt: state.snapshot.topStations?.capturedAt),
            ),
        )
        genresError = nil
        refreshError = nil
        return SavedContentDecision(
            stationsAreFresh: state.isFresh,
            needsGenres: state.isFresh && state.snapshot.genres == nil,
        )
    }

    /// Fills the genre strip without touching the station list already on screen.
    private func fillInGenres(generation: Int) async {
        let (genres, error) = await Self.loadGenres(from: directory)
        guard refreshGeneration == generation else { return }
        genresError = error
        guard error == nil, case let .loaded(content) = phase else { return }
        phase = .loaded(
            BrowseContent(
                spotlight: content.spotlight,
                stations: content.stations,
                genres: genres,
                origin: content.origin,
            ),
        )
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

            phase = .loaded(
                BrowseContent(
                    spotlight: stations.first,
                    stations: stations,
                    genres: genres,
                    origin: .live,
                ),
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
        from directory: any RadioDirectoryProviding,
    ) async -> ([Genre], RadioDirectoryError?) {
        do {
            return (try await directory.genres(), nil)
        } catch {
            return ([], error)
        }
    }

    public func toggleGenreFilter(_ genre: String) {
        if selectedGenre == genre {
            genreTask?.cancel()
            selectedGenre = nil
            genrePhase = nil
            return
        }

        beginGenreLoad(genre)
    }

    /// Fetches the genre already on screen again. Try Again uses this;
    /// `toggleGenreFilter` would clear the filter instead.
    public func reloadGenreFilter() {
        guard let selectedGenre else { return }
        beginGenreLoad(selectedGenre)
    }

    private func beginGenreLoad(_ genre: String) {
        genreTask?.cancel()
        selectedGenre = genre
        genrePhase = .loading

        genreTask = Task { [weak self] in
            guard let self else { return }
            let phase = await Self.genrePhase(for: genre, from: directory)
            guard Task.isCancelled == false, self.selectedGenre == genre else { return }
            self.genrePhase = phase
        }
    }

    private static func genrePhase(
        for genre: String,
        from directory: any RadioDirectoryProviding,
    ) async -> GenreStationsPhase {
        do {
            let stations = try await directory.stations(
                inGenre: genre,
                limit: Configuration.genreStationsLimit,
            )
            return .loaded(stations)
        } catch let error as RadioDirectoryError {
            return .failed(error)
        } catch {
            return .failed(.transport(error.localizedDescription))
        }
    }
}
