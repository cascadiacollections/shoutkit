import Foundation
import BrowseFeature
import DesignSystem
import LibraryFeature
import Persistence
import PlayerFeature
import Playback
import RadioDirectory
import SearchFeature
import SettingsFeature
import SwiftUI

struct RootView: View {
    let launchRouter: StationLaunchRouter

    // Read only to verify injection below; feature views read these themselves.
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library

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

    private var currentHandoffLink: StationLink? {
        guard let playback else { return nil }

        switch playback.state {
        case let .loading(station),
             let .buffering(station),
             let .playing(station):
            return StationLink(station: station)
        case .idle, .paused, .failed:
            return nil
        }
    }
}

private enum ShoutKitTab: Hashable {
    case listenNow
    case browse
    case search
    case favorites
}

#Preview {
    RootView(launchRouter: StationLaunchRouter())
        .tint(.shoutKitAccent)
}
