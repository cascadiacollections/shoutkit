import BackgroundTasks
import Foundation
import OSLog
import Persistence
import RadioDirectory

@MainActor
final class BackgroundRefreshController {
    private static let taskIdentifierSuffix = ".app-refresh"
    private static let topStationsLimit = 24
    /// Refresh every few hours: often enough to keep directory snapshots warm,
    /// infrequent enough to stay firmly in "best effort" territory.
    private static let refreshInterval: TimeInterval = 4 * 3600

    static var taskIdentifier: String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.cascadiacollections.shoutkit"
        return "\(bundleIdentifier)\(taskIdentifierSuffix)"
    }

    private let logger = Logger(subsystem: "ShoutKit.App", category: "BackgroundRefresh")
    private var isRegistered = false

    func register() {
        guard isRegistered == false else { return }

        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(refreshTask)
        }

        if isRegistered == false {
            logger.error("Failed to register background refresh task")
        }
    }

    func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Failed to schedule background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()

        let refreshTask = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.runRefresh()
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }

        Task { @MainActor in
            let success = await refreshTask.value
            task.setTaskCompleted(success: success)
        }
    }

    private func runRefresh() async -> Bool {
        guard Task.isCancelled == false else { return false }

        // `bootstrap()` is app-global and idempotent: foreground launches reuse
        // the existing dependency graph, while a background-only launch rebuilds
        // the same single set of services the app would normally construct.
        let services = AppDependencies.bootstrap()
        let favoriteStations = services.libraryStore.favoriteStations()

        await refreshFavoriteStreamURLSnapshots(
            favoriteStations,
            store: services.libraryStore,
            directory: services.directory
        )
        let didWarmTopStations = await warmTopStationsCache(using: services.directory)
        await warmGenresCache(using: services.directory)

        return Task.isCancelled == false && didWarmTopStations
    }

    private func refreshFavoriteStreamURLSnapshots(
        _ favoriteStations: [Station],
        store: LibraryStore,
        directory: any RadioDirectoryProviding
    ) async {
        for favorite in favoriteStations {
            guard Task.isCancelled == false else { return }

            do {
                let endpoint = try await directory.streamEndpoint(for: stationNeedingFreshEndpoint(from: favorite))
                store.refreshStreamURLSnapshot(stationID: favorite.id, streamURL: endpoint.url)
            } catch let error as RadioDirectoryError {
                logger.debug(
                    """
                    Background refresh skipped station \(favorite.id, privacy: .public): \
                    \(String(describing: error), privacy: .public)
                    """
                )
            } catch {
                logger.debug(
                    """
                    Background refresh skipped station \(favorite.id, privacy: .public): \
                    \(error.localizedDescription, privacy: .public)
                    """
                )
            }
        }
    }

    private func warmTopStationsCache(using directory: any RadioDirectoryProviding) async -> Bool {
        do {
            _ = try await directory.topStations(limit: Self.topStationsLimit)
            return true
        } catch let error as RadioDirectoryError {
            logger.debug("Background refresh failed to warm top stations: \(String(describing: error), privacy: .public)")
            return false
        } catch {
            logger.debug(
                "Background refresh failed to warm top stations: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func warmGenresCache(using directory: any RadioDirectoryProviding) async {
        do {
            _ = try await directory.genres()
        } catch let error as RadioDirectoryError {
            logger.debug("Background refresh failed to warm genres: \(String(describing: error), privacy: .public)")
        } catch {
            logger.debug("Background refresh failed to warm genres: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stationNeedingFreshEndpoint(from station: Station) -> Station {
        // Radio-Browser station IDs are UUIDs. Clearing the snapshotted URL for
        // those IDs forces `streamEndpoint(for:)` down its by-UUID re-resolution
        // path so a rotated upstream stream URL can be refreshed. Non-UUID IDs
        // (curated stations, SHOUTcast) either aren't re-resolvable that way or
        // already ignore the snapshot in their stream-endpoint implementation.
        guard station.preferredStreamURL != nil, UUID(uuidString: station.id) != nil else {
            return station
        }

        return Station(
            id: station.id,
            name: station.name,
            genre: station.genre,
            tags: station.tags,
            country: station.country,
            codec: station.codec,
            language: station.language,
            listenerCount: station.listenerCount,
            bitrate: station.bitrate,
            clickTrend: station.clickTrend,
            votes: station.votes,
            artworkURL: station.artworkURL,
            preferredStreamURL: nil
        )
    }
}
