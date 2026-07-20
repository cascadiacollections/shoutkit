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
    private let swipeTabThreshold: CGFloat = 70

    let launchRouter: StationLaunchRouter
    let isPersistentStoreAvailable: Bool

    // Read only to verify injection below; feature views read these themselves.
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library

    // Favorites, mirrored to the Home Screen quick-play widget on change. Sorted
    // to match the Favorites tab so the widget's picker shows the same order.
    @Query(sort: \FavoriteStation.sortIndex, order: .forward)
    private var favorites: [FavoriteStation]

    @State private var selectedTab = ShoutKitTab.listenNow
    @State private var isShowingNowPlaying = false
    @State private var isShowingSettings = false
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
                NowPlayingView()
                    .presentationDetents([.large])
                    .presentationBackground(.regularMaterial)
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
                guard let link else { return }
                launchRouter.clearPending()
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
            .simultaneousGesture(
                DragGesture()
                    .onEnded { value in
                        handleTabSwipe(value)
                    }
            )
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Listen Now", systemImage: "play.circle", value: ShoutKitTab.listenNow) {
                NavigationStack {
                    ListenNowView(viewModel: BrowseViewModel())
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

            Tab("Browse", systemImage: "square.grid.2x2", value: ShoutKitTab.browse) {
                NavigationStack {
                    BrowseLandingView(viewModel: BrowseViewModel())
                        .navigationTitle("Browse")
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: ShoutKitTab.search, role: .search) {
                NavigationStack {
                    SearchView(viewModel: SearchViewModel())
                        .navigationTitle("Search")
                }
            }

            Tab("Favorites", systemImage: "heart", value: ShoutKitTab.favorites) {
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

    /// An `Equatable` fingerprint of the favorites list — station ids in display
    /// order — so `onChange` fires on add, remove, and reorder without depending
    /// on `[FavoriteStation]` element equality.
    private var favoritesSignature: [String] {
        favorites.map(\.stationID)
    }

    private var currentHandoffLink: StationLink? {
        guard let station = playback?.state.handoffStation else { return nil }
        return StationLink(station: station)
    }

    private func handleTabSwipe(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height

        guard abs(horizontal) > abs(vertical), abs(horizontal) >= swipeTabThreshold else { return }
        if horizontal < 0 {
            selectedTab = selectedTab.next ?? selectedTab
        } else {
            selectedTab = selectedTab.previous ?? selectedTab
        }
    }
}

private enum ShoutKitTab: Hashable, CaseIterable {
    case listenNow
    case browse
    case search
    case favorites

    var next: Self? {
        guard let index = Self.allCases.firstIndex(of: self), index < Self.allCases.count - 1 else { return nil }
        return Self.allCases[index + 1]
    }

    var previous: Self? {
        guard let index = Self.allCases.firstIndex(of: self), index > 0 else { return nil }
        return Self.allCases[index - 1]
    }
}

#Preview {
    RootView(
        launchRouter: StationLaunchRouter(),
        isPersistentStoreAvailable: true
    )
        .tint(.shoutKitAccent)
}
