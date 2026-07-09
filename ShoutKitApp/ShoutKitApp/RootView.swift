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
    let directory: any RadioDirectoryProviding

    // Read only to verify injection below; feature views read these themselves.
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library

    @State private var selectedTab = ShoutKitTab.listenNow
    @State private var isShowingNowPlaying = false
    @State private var isShowingSettings = false
    @State private var stationLaunchTask: Task<Void, Never>?
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
            .onAppear {
                stationLaunchTask?.cancel()
                stationLaunchTask = Task { @MainActor in
                    // Every feature view optional-chains these, so a missing injection
                    // fails silently (taps do nothing) rather than crashing — easy to
                    // miss outside of active testing. Catch it loudly in Debug.
                    assertEnvironmentInjected(playback != nil, "PlaybackController was not injected at the app root")
                    assertEnvironmentInjected(library != nil, "LibraryStore was not injected at the app root")
                    if let request = await StationLaunchCoordinator.shared.activateListener() {
                        handle(request)
                    }

                    for await notification in NotificationCenter.default.notifications(
                        named: StationLaunchCoordinator.notificationName
                    ) {
                        if Task.isCancelled {
                            break
                        }

                        guard let request = notification.object as? StationLaunchRequest else { continue }
                        handle(request)
                    }
                }
            }
            .onDisappear {
                stationLaunchTask?.cancel()
                stationLaunchTask = nil
                Task {
                    await StationLaunchCoordinator.shared.deactivateListener()
                }
            }
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Listen Now", systemImage: "play.circle", value: ShoutKitTab.listenNow) {
                NavigationStack {
                    ListenNowView(viewModel: BrowseViewModel(directory: directory))
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
                    BrowseLandingView(viewModel: BrowseViewModel(directory: directory))
                        .navigationTitle("Browse")
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: ShoutKitTab.search, role: .search) {
                NavigationStack {
                    SearchView(viewModel: SearchViewModel(directory: directory))
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
    }

    private func handle(_ request: StationLaunchRequest) {
        let link = request.link
        selectedTab = .listenNow
        isShowingNowPlaying = link.presentNowPlaying

        if link.autoPlay {
            playback?.play(link.station)
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
    RootView(directory: PreviewRadioDirectory())
        .tint(.shoutKitAccent)
}
