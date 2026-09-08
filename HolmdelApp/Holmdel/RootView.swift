import Foundation
import BrowseFeature
import BrowseFeatureCore
import DesignSystem
import LibraryFeature
import Persistence
import PlayerFeature
import Playback
import RadioDirectory
import SearchFeature
import SearchFeatureCore
import SettingsFeature
import SwiftData
import SwiftUI

struct RootView: View {
    let launchRouter: StationLaunchRouter
    let isPersistentStoreAvailable: Bool

    // Read only to verify injection below; feature views read these themselves.
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library

    // Favorites, mirrored to the Home Screen quick-play widget on change. Sorted
    // to match the Favorites tab so the widget's picker shows the same order.
    @Query(sort: \FavoriteStation.sortIndex, order: .forward)
    private var favorites: [FavoriteStation]

    @State private var selectedTab = HolmdelTab.listenNow
    @State private var isShowingNowPlaying = false
    @State private var isShowingSettings = false
    @State private var listenNowViewModel = BrowseViewModel()
    @State private var searchViewModel = SearchViewModel()
    // Bumped whenever the Search tab is re-tapped while already selected, so
    // SearchView can refocus its search field (Apple Music re-tap behavior).
    // `selectedTab` itself doesn't change on reselection, so `onChange` alone
    // can't observe it — this binding's `set` fires on every tap regardless.
    @State private var searchReactivationToken = 0
    @AppStorage("hasCompletedFirstRun") private var hasCompletedFirstRun = false

    var body: some View {
        tabView
            // Always attached: conditionally applying this modifier changes the
            // TabView's structural identity and resets every tab's navigation and
            // scroll state whenever playback starts or stops. At idle the
            // mini-player renders a "Not Playing" placeholder (Apple Music pattern).
            .tabViewBottomAccessory {
                MiniPlayerView {
                    isShowingNowPlaying = true
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .sheet(isPresented: $isShowingNowPlaying) {
                // No `presentationBackground`: `NowPlayingView`'s own ambient
                // backdrop fills the sheet edge to edge, so a material behind it
                // was a layer nobody could ever see.
                NowPlayingView()
                    .presentationDetents([.large])
            }
            .fullScreenCover(isPresented: .init(get: { hasCompletedFirstRun == false }, set: { _ in })) {
                WelcomeOverlayView {
                    hasCompletedFirstRun = true
                }
            }
            .task {
                // Every feature view optional-chains these, so a missing injection
                // fails silently (taps do nothing) rather than crashing — easy to
                // miss outside of active testing. Catch it loudly in Debug.
                assertEnvironmentInjected(playback != nil, "PlaybackController was not injected at the app root")
                assertEnvironmentInjected(library != nil, "LibraryStore was not injected at the app root")
            }
            // `initial: true` drains a link that arrived before this view existed
            // (cold launch via deep link), so no listener handshake is needed.
            .onChange(of: launchRouter.pending, initial: true) { _, link in
                guard let link, launchRouter.consumePending(link) else { return }
                handle(link)
            }
            // Keep the quick-play widget's favorite list in sync. `initial: true`
            // covers cold launch; the signature captures membership *and* order,
            // so a drag-reorder republishes too. Skip writes when SwiftData is
            // running on an in-memory fallback to avoid clobbering a last-known-
            // good widget snapshot with an empty list.
            .onChange(of: favoritesSignature, initial: true) {
                guard isPersistentStoreAvailable else { return }
                QuickPlayWidgetPublisher.publish(favorites)
            }
            .onContinueUserActivity(StationLink.handoffActivityType) { activity in
                launchRouter.open(userActivity: activity)
            }
            .userActivity(
                StationLink.handoffActivityType,
                isActive: currentHandoffLink != nil
            ) { activity in
                guard let link = currentHandoffLink else { return }
                let userInfo = link.handoffUserInfo
                activity.title = "Resume \(link.station.name)"
                activity.isEligibleForHandoff = true
                activity.targetContentIdentifier = link.station.id
                activity.requiredUserInfoKeys = Set(userInfo.keys)
                activity.userInfo = userInfo
            }
            // Deliberately no root-level swipe-between-tabs gesture. A
            // `simultaneousGesture(DragGesture())` here fires *in addition to*
            // whatever the child handled, so a horizontal drag past the
            // threshold also switched tabs while the user was scrolling a
            // `StationCarousel`, swiping a row to delete in Favorites or the
            // Listen Now teaser, or using the interactive back-swipe in a
            // `NavigationStack`. Constraining it doesn't rescue it: the only
            // filter that separates it from those (start near a screen edge)
            // is the back-swipe's own trigger. Apple Music and the system
            // `TabView` don't page between tabs either, so matching them is
            // both the safe and the expected behavior.
    }

    /// Three tabs, each answering a different question: what should I play, what
    /// exists, what's mine.
    ///
    /// There was a fourth — Browse — and it answered the same question as Listen
    /// Now with the same `topStations` fetch, rendered as a carousel above a grid
    /// of the same ten stations, plus a genre strip that duplicated the one in
    /// Search. Listen Now absorbed the station list; Search kept genres and got a
    /// real genre query instead of a name search.
    private var tabView: some View {
        TabView(selection: tabSelection) {
            Tab("Listen Now", systemImage: "play.circle", value: HolmdelTab.listenNow) {
                NavigationStack {
                    ListenNowView(viewModel: listenNowViewModel)
                        .navigationTitle("Listen Now")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Settings", systemImage: "gearshape") {
                                    isShowingSettings = true
                                }
                            }
                        }
                        .sheet(isPresented: $isShowingSettings) {
                            SettingsView()
                        }
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: HolmdelTab.search, role: .search) {
                NavigationStack {
                    SearchView(viewModel: searchViewModel, reactivationToken: searchReactivationToken)
                        .navigationTitle("Search")
                }
            }

            Tab("Favorites", systemImage: "heart", value: HolmdelTab.favorites) {
                NavigationStack {
                    LibraryView()
                        .navigationTitle("Favorites")
                }
            }
        }
        // iPhone keeps the bottom tab bar; iPad gets the Apple Music-style
        // sidebar with a user toggle back to a top tab bar.
        .tabViewStyle(.sidebarAdaptable)
    }

    private func handle(_ link: StationLink) {
        selectedTab = .listenNow
        // An absent flag is inert — it must not yank down a sheet the user is in.
        if link.presentNowPlaying {
            isShowingNowPlaying = true
        }

        guard link.autoPlay, let playback else { return }

        // A repeated link must not tear down and reconnect a live stream.
        switch playback.phase(for: link.station) {
        case .playing, .loading:
            break
        case .paused, .failed:
            playback.resume()
        case .idle:
            playback.play(link.station)
        }
    }

    /// An `Equatable` fingerprint of the favorites list — station ids and stream
    /// snapshots in display order — so `onChange` fires on add/remove/reorder and
    /// on stream-URL refreshes without depending on `[FavoriteStation]` equality.
    private var favoritesSignature: [String] {
        favorites.map { "\($0.stationID)|\($0.streamURLString ?? "")" }
    }

    private var currentHandoffLink: StationLink? {
        guard let station = playback?.state.handoffStation else { return nil }
        return StationLink(station: station)
    }

    /// Wraps `selectedTab` so re-tapping the already-selected Search tab is
    /// observable. `TabView` writes through this binding on every tap, even
    /// when the value doesn't change, unlike a plain `@State` + `onChange`.
    private var tabSelection: Binding<HolmdelTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .search, selectedTab == .search {
                    searchReactivationToken += 1
                }
                selectedTab = newValue
            }
        )
    }
}

private enum HolmdelTab: Hashable {
    case listenNow
    case search
    case favorites
}

#Preview {
    RootView(
        launchRouter: StationLaunchRouter(),
        isPersistentStoreAvailable: true
    )
        .tint(.shoutKitAccent)
}
