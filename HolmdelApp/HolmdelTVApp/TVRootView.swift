import Persistence
import Playback
import RadioDirectory
import SwiftData
import SwiftUI

/// The whole tvOS UI: a now-playing banner over two horizontal station shelves.
///
/// Written for the focus engine rather than adapted from the phone: no `List`, no
/// `NavigationStack` drill-down, and nothing that depends on a gesture. Every control
/// is a `Button` inside a `.focusSection()`, so the Siri Remote's directional pad
/// reaches all of them and tvOS draws the focus effect itself. Shelves scroll
/// horizontally because that is the direction the remote's swipe maps to, and the
/// vertical axis moves between shelves.
struct TVRootView: View {
    @Environment(\.playbackController) private var playback
    @Environment(\.tvDirectory) private var directory
    @Query(sort: \RecentStation.playedAt, order: .reverse) private var recents: [RecentStation]

    @State private var topStations: [Station] = []
    @State private var loadFailure: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 48) {
                nowPlayingBanner
                    .focusSection()

                if !recentStations.isEmpty {
                    shelf(title: "Recent Stations", stations: recentStations)
                        .focusSection()
                }

                topStationsShelf
                    .focusSection()
            }
            .padding(60)
        }
        .task { await loadTopStations() }
    }

    // MARK: - Now playing

    private var nowPlayingBanner: some View {
        HStack(alignment: .top, spacing: 40) {
            artwork(for: playback?.currentStation, size: 220)

            VStack(alignment: .leading, spacing: 16) {
                Text(playback?.currentStation?.name ?? "Holmdel")
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(2)

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let playback, playback.currentStation != nil {
                    transportControls(playback)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func transportControls(_ playback: PlaybackController) -> some View {
        HStack(spacing: 24) {
            Button {
                playback.togglePlayPause()
            } label: {
                Label(
                    isPlaying(playback) ? "Pause" : "Play",
                    systemImage: isPlaying(playback) ? "pause.fill" : "play.fill"
                )
            }

            Button {
                playback.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        }
        .padding(.top, 8)
    }

    /// The current track, once ICY metadata arrives from
    /// `AudioStreamingPlaybackEngine`. Genre is the fallback rather than the norm: a
    /// station may send no metadata at all, and the first title lands a beat after
    /// playback starts, so this line has to read sensibly with `nowPlaying` still nil.
    private var subtitle: String {
        guard let playback, let station = playback.currentStation else {
            return "Pick a station to start listening."
        }
        if let track = playback.nowPlaying, let title = track.title {
            if let artist = track.artist {
                return "\(title) — \(artist)"
            }
            return title
        }
        return station.genre
    }

    // MARK: - Shelves

    private var topStationsShelf: some View {
        Group {
            if isLoading {
                shelfPlaceholder(title: "Popular Stations", message: "Loading stations…")
            } else if let loadFailure {
                shelfPlaceholder(title: "Popular Stations", message: loadFailure)
            } else if topStations.isEmpty {
                shelfPlaceholder(title: "Popular Stations", message: "No stations found.")
            } else {
                shelf(title: "Popular Stations", stations: topStations)
            }
        }
    }

    private func shelf(title: String, stations: [Station]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2.weight(.semibold))

            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(stations, id: \.id) { station in
                        stationCard(station)
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
    }

    private func shelfPlaceholder(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func stationCard(_ station: Station) -> some View {
        Button {
            playback?.toggle(station)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                artwork(for: station, size: 240)

                Text(station.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(station.genre)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 240)
        }
        .buttonStyle(.card)
    }

    // MARK: - Artwork

    private func artwork(for station: Station?, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)

            if let url = station?.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    stationSymbol
                }
            } else {
                stationSymbol
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var stationSymbol: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
    }

    // MARK: - Data

    private var recentStations: [Station] {
        recents.prefix(10).map(\.station)
    }

    private func loadTopStations() async {
        guard let directory else {
            isLoading = false
            return
        }
        do {
            topStations = try await directory.topStations(limit: 30)
            loadFailure = nil
        } catch {
            loadFailure = error.localizedDescription
        }
        isLoading = false
    }

    private func isPlaying(_ playback: PlaybackController) -> Bool {
        if case .playing = playback.state {
            return true
        }
        return false
    }
}
