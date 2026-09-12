@testable import BrowseFeatureCore
import Foundation
import RadioDirectory
import Testing

/// Scriptable ``DirectoryDiscoveryCaching`` double: hands back a saved snapshot
/// and records whether the view model asked for the in-memory window to be
/// dropped (which is how a user-initiated refresh forces a real fetch).
private actor FakeDiscoveryCache: DirectoryDiscoveryCaching {
    private let state: DirectoryDiscoverySnapshotState?
    private(set) var invalidateCount = 0

    init(state: DirectoryDiscoverySnapshotState?) {
        self.state = state
    }

    func discoverySnapshotState() async -> DirectoryDiscoverySnapshotState? {
        state
    }

    func invalidateMemoryCache() async {
        invalidateCount += 1
    }
}

private let capturedAt = Date(timeIntervalSinceReferenceDate: 0)

private func savedState(isFresh: Bool) -> DirectoryDiscoverySnapshotState {
    DirectoryDiscoverySnapshotState(
        snapshot: DirectoryDiscoverySnapshot(
            topStations: DirectoryDiscoverySnapshot.TopStations(
                stations: [.fixture(id: "saved", name: "Saved Station")],
                limit: 24,
                capturedAt: capturedAt,
            ),
            genres: DirectoryDiscoverySnapshot.Genres(
                genres: [Genre(name: "Saved Genre")],
                capturedAt: capturedAt,
            ),
            sourceIdentity: "test",
        ),
        isFresh: isFresh,
    )
}

@MainActor
struct BrowseSavedContentTests {
    @Test func `fresh saved content paints without touching the directory`() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.success([.fixture(id: "live", name: "Live Station")]))
        let viewModel = BrowseViewModel(
            directory: directory,
            discoveryCache: FakeDiscoveryCache(state: savedState(isFresh: true)),
        )

        await viewModel.refresh()

        guard case let .loaded(content) = viewModel.phase else {
            Issue.record("Expected .loaded, got \(viewModel.phase)")
            return
        }
        // Inside its window the snapshot is the whole answer: instant paint, no
        // request, and the same list as the previous launch.
        #expect(content.stations.map(\.id) == ["saved"])
        #expect(content.genres == [Genre(name: "Saved Genre")])
        #expect(content.origin == .saved(capturedAt: capturedAt))
        #expect(await directory.topStationsCallCount == 0)
    }

    @Test func `stale saved content is replaced by live content`() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.success([.fixture(id: "live", name: "Live Station")]))
        let viewModel = BrowseViewModel(
            directory: directory,
            discoveryCache: FakeDiscoveryCache(state: savedState(isFresh: false)),
        )

        await viewModel.refresh()

        guard case let .loaded(content) = viewModel.phase else {
            Issue.record("Expected .loaded, got \(viewModel.phase)")
            return
        }
        #expect(content.stations.map(\.id) == ["live"])
        #expect(content.origin == .live)
        #expect(viewModel.refreshError == nil)
    }

    @Test func `saved content survives A failed fetch`() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.failure(.transport("offline")))
        let viewModel = BrowseViewModel(
            directory: directory,
            discoveryCache: FakeDiscoveryCache(state: savedState(isFresh: false)),
        )

        await viewModel.refresh()

        guard case let .loaded(content) = viewModel.phase else {
            Issue.record("Expected saved content to survive the failure, got \(viewModel.phase)")
            return
        }
        // The stations played fine last time and the app is offline, not broken —
        // an error page here would be strictly worse than the list.
        #expect(content.stations.map(\.id) == ["saved"])
        #expect(content.origin == .saved(capturedAt: capturedAt))
        #expect(viewModel.refreshError == .transport("offline"))
    }

    @Test func `failed fetch with nothing saved still fails`() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.failure(.transport("offline")))
        let viewModel = BrowseViewModel(
            directory: directory,
            discoveryCache: FakeDiscoveryCache(state: nil),
        )

        await viewModel.refresh()

        #expect(viewModel.phase == .failed(.transport("offline")))
    }

    @Test func `empty live response does not blank saved content`() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.success([]))
        let viewModel = BrowseViewModel(
            directory: directory,
            discoveryCache: FakeDiscoveryCache(state: savedState(isFresh: false)),
        )

        await viewModel.refresh()

        guard case let .loaded(content) = viewModel.phase else {
            Issue.record("Expected saved content to survive an empty response, got \(viewModel.phase)")
            return
        }
        #expect(content.stations.map(\.id) == ["saved"])
    }

    @Test func `user initiated refresh skips saved content and forces A fetch`() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.success([.fixture(id: "live", name: "Live Station")]))
        let cache = FakeDiscoveryCache(state: savedState(isFresh: true))
        let viewModel = BrowseViewModel(directory: directory, discoveryCache: cache)

        await viewModel.refresh(source: .userInitiated)

        guard case let .loaded(content) = viewModel.phase else {
            Issue.record("Expected .loaded, got \(viewModel.phase)")
            return
        }
        // Pull-to-refresh means the network, even with a fresh snapshot on disk
        // and a warm in-memory window behind the directory.
        #expect(content.stations.map(\.id) == ["live"])
        #expect(content.origin == .live)
        #expect(await cache.invalidateCount == 1)
        #expect(await directory.topStationsCallCount == 1)
    }

    @Test func `refresh without A cache behaves like A plain live fetch`() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.success([.fixture(id: "live", name: "Live Station")]))
        let viewModel = BrowseViewModel(
            directory: directory,
            discoveryCache: UnavailableDirectoryDiscoveryCache(),
        )

        await viewModel.refresh()

        guard case let .loaded(content) = viewModel.phase else {
            Issue.record("Expected .loaded, got \(viewModel.phase)")
            return
        }
        #expect(content.stations.map(\.id) == ["live"])
        #expect(content.origin == .live)
    }
}
