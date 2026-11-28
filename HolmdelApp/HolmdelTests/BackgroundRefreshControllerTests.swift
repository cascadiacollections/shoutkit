import Foundation
@testable import Holmdel
import Persistence
import RadioDirectory
import SwiftData
import Testing

/// The flag a background wake hands `BGAppRefreshTask.setTaskCompleted(success:)`.
/// iOS uses it to decide how often to wake the app, so a directory error in one
/// best-effort step must not report the whole wake as failed (#283).
@MainActor
struct BackgroundRefreshControllerTests {
    private let store = LibraryStore(context: ModelContext(ShoutKitModelContainer.makeContainer(inMemory: true)))

    @Test func `a wake whose directory warm-ups fail still succeeds`() async {
        let directory = FailingDirectory()

        let success = await BackgroundRefreshController().refresh(
            store: store,
            directory: directory,
            discoveryCache: UnavailableDirectoryDiscoveryCache(),
        )

        #expect(success)
        #expect(await directory.topStationsCalls == 1)
        #expect(await directory.genresCalls == 1)
    }

    @Test func `a cancelled wake fails`() async {
        let controller = BackgroundRefreshController()
        let directory = FailingDirectory()
        // The task inherits the main actor, so it cannot start before `cancel()`.
        let wake = Task {
            await controller.refresh(
                store: store,
                directory: directory,
                discoveryCache: UnavailableDirectoryDiscoveryCache(),
            )
        }
        wake.cancel()

        #expect(await wake.value == false)
    }
}

/// A directory that is down: every call fails.
private actor FailingDirectory: RadioDirectoryProviding {
    private(set) var topStationsCalls = 0
    private(set) var genresCalls = 0

    func genres() async throws(RadioDirectoryError) -> [Genre] {
        genresCalls += 1
        throw .httpStatus(503)
    }

    func topStations(limit _: Int) async throws(RadioDirectoryError) -> [Station] {
        topStationsCalls += 1
        throw .httpStatus(503)
    }

    func searchStations(matching _: String, limit _: Int) async throws(RadioDirectoryError) -> [Station] {
        throw .httpStatus(503)
    }

    func streamEndpoint(for _: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        throw .httpStatus(503)
    }
}
